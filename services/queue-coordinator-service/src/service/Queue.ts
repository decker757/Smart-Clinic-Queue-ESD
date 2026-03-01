/*
This serves to differentiate between the 2 queues (generic queue vs specific doctor queue) and handle the exceptions.

Exceptions that need to be handled:
1. Patient does not appear (in the context of did/did not reply check in)
2. Patient late (in the context of checking in)
3. Patient early (Unsure of how to handle this since other patients that booked earlier will have higher priority unless many people infront cancelled/late.)

Case(s) not handled:
1. Emergency queue -> patient would have went A&E and not a GP clinic/polyclinic.

BTL:
1. Redis to cache patient's current position in the queue
*/

import { AppointmentInfo, QueueEntry } from "../model/Queue";
import pool from "../db/db";

export async function addToQueue(appointment: AppointmentInfo): Promise<QueueEntry> {
    try {
        // pick sequence based on session (generic) or start_time hour (specific doctor)
        let isAfternoon: boolean;
        if (appointment.session) {
            isAfternoon = appointment.session === "afternoon";
        } else if (appointment.start_time) {
            isAfternoon = new Date(appointment.start_time).getUTCHours() >= 5; // 13:00 SGT = 05:00 UTC
        } else {
            isAfternoon = false; // fallback
        }
        const sequenceName = isAfternoon
            ? "queue_number_afternoon_seq"
            : "queue_number_morning_seq";

        const { rows: seqRows } = await pool.query(`SELECT NEXTVAL('queue.${sequenceName}') AS queue_number`);
        const queue_number = seqRows[0].queue_number;

        const { rows } = await pool.query(`
            INSERT INTO queue.queue_entries (appointment_id, patient_id, doctor_id, session, queue_number, status)
            VALUES ($1, $2, $3, $4, $5, 'waiting')
            RETURNING *
        `, [
            appointment.appointment_id,
            appointment.patient_id,
            appointment.doctor_id ?? null,
            appointment.session ?? null,
            queue_number,
        ]);

        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error adding to queue:", e);
        throw e;
    }
}

export async function getQueuePosition(appointment_id: string){
    try{
        const response = await pool.query(`
            SELECT queue_number, estimated_time FROM queue.queue_entries WHERE
            appointment_id = $1;
        `, [
            appointment_id
        ]);
        if (!response.rows[0]){
            throw new Error("Appointment not in queue");
        }
        return response.rows[0];

    } catch (e){
        console.error("Error fetching queue:", e);
        throw e;
    }
}

export async function removeFromQueue(appointment_id: string){
    try{
        const response = await pool.query(`
            UPDATE queue.queue_entries SET status = 'cancelled', estimated_time = null
            WHERE appointment_id = $1
            RETURNING *
        `,
        [
            appointment_id
        ]
        );

        if (!response.rows[0]) throw new Error("Appointment not in queue");
        return response.rows[0];

    }catch (e){
        console.error("Error removing from queue:", e);
        throw e;
    }
}

export async function checkIn(appointment_id: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(
            `SELECT * FROM queue.queue_entries WHERE appointment_id = $1`,
            [appointment_id]
        );
        if (!rows[0]) throw new Error("Appointment not in queue");
        const entry = rows[0] as QueueEntry;

        if (entry.status === "waiting") {
            // Normal check-in — patient confirmed present
            const { rows: updated } = await pool.query(`
                UPDATE queue.queue_entries SET status = 'checked_in', updated_at = NOW()
                WHERE appointment_id = $1 RETURNING *
            `, [appointment_id]);
            return updated[0] as QueueEntry;
        }

        if (entry.status === "skipped") {
            // Late arrival — rejoin at the back of the queue with a new number
            const sequenceName = entry.session === "afternoon"
                ? "queue_number_afternoon_seq"
                : "queue_number_morning_seq";
            const { rows: seqRows } = await pool.query(
                `SELECT NEXTVAL('queue.${sequenceName}') AS queue_number`
            );
            const newQueueNumber = seqRows[0].queue_number;
            const { rows: updated } = await pool.query(`
                UPDATE queue.queue_entries
                SET status = 'waiting', queue_number = $2, updated_at = NOW()
                WHERE appointment_id = $1 RETURNING *
            `, [appointment_id, newQueueNumber]);
            return updated[0] as QueueEntry;
        }

        throw new Error(`Cannot check in: current status is '${entry.status}'`);
    } catch (e) {
        console.error("Error checking in:", e);
        throw e;
    }
}

export async function markNoShow(appointment_id: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(`
            UPDATE queue.queue_entries SET status = 'skipped', updated_at = NOW()
            WHERE appointment_id = $1 AND status IN ('waiting', 'checked_in', 'called')
            RETURNING *
        `, [appointment_id]);
        if (!rows[0]) throw new Error("Appointment not found or already resolved");
        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error marking no-show:", e);
        throw e;
    }
}

export async function callNext(session: string, doctor_id?: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(`
            UPDATE queue.queue_entries
            SET status = 'called', updated_at = NOW()
            WHERE id = (
                SELECT id FROM queue.queue_entries
                WHERE status IN ('waiting', 'checked_in')
                  AND session = $1
                  AND ($2::uuid IS NULL OR doctor_id = $2::uuid)
                ORDER BY
                    -- checked_in patients go first (confirmed present), then waiting
                    CASE status WHEN 'checked_in' THEN 0 ELSE 1 END ASC,
                    queue_number ASC
                LIMIT 1
            )
            RETURNING *
        `, [session, doctor_id ?? null]);

        if (!rows[0]) throw new Error("No waiting patients in queue");

        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error calling next patient:", e);
        throw e;
    }
}

export async function resetDailyQueue(){
    try{
        await pool.query(`DELETE FROM queue.queue_entries`);
        await pool.query(`ALTER SEQUENCE queue.queue_number_morning_seq RESTART WITH 1`);
        await pool.query(`ALTER SEQUENCE queue.queue_number_afternoon_seq RESTART WITH 1`);
        
    }catch (e){
        console.error("Failed to reset queue:", e);
        throw e;
    }
}