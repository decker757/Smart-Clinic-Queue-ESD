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
import redis from "../db/redis";

const CACHE_TTL = 10; // seconds
const cacheKey = (appointment_id: string) => `queue:position:${appointment_id}`;

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

        const { rows } = await pool.query(`
            INSERT INTO queue.queue_entries (appointment_id, patient_id, doctor_id, session, queue_number, status)
            VALUES ($1, $2, $3, $4, NEXTVAL('queue.${sequenceName}'), 'waiting')
            RETURNING *
        `, [
            appointment.appointment_id,
            appointment.patient_id,
            appointment.doctor_id ?? null,
            appointment.session ?? null,
        ]);

        await redis.del(cacheKey(appointment.appointment_id));
        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error adding to queue:", e);
        throw e;
    }
}

export async function getQueuePosition(appointment_id: string, callerId?: string){
    try{
        // Ownership check: cache doesn't store patient_id, so always verify from DB
        // when a caller identity is present.
        if (callerId) {
            const { rows: ownerRows } = await pool.query(
                `SELECT patient_id FROM queue.queue_entries WHERE appointment_id = $1`,
                [appointment_id],
            );
            if (ownerRows.length > 0 && ownerRows[0].patient_id !== callerId) {
                throw new Error("Forbidden");
            }
        }

        try {
            const cached = await redis.get(cacheKey(appointment_id));
            if (cached) {
                console.log(`[Redis] cache hit for ${appointment_id}`);
                return JSON.parse(cached);
            }
        } catch {
            console.warn("[Redis] unavailable, falling back to DB");
        }

        const response = await pool.query(`
            SELECT e.queue_number, e.estimated_time, e.status, e.doctor_id, e.session,
                   (SELECT COUNT(*) FROM queue.queue_entries a
                    WHERE a.queue_number < e.queue_number
                      AND a.status NOT IN ('done', 'cancelled')
                      AND (
                        (e.doctor_id IS NOT NULL AND a.doctor_id = e.doctor_id)
                        OR
                        (e.doctor_id IS NULL AND a.session = e.session AND a.doctor_id IS NULL)
                      )
                   ) AS active_ahead
            FROM queue.queue_entries e
            WHERE e.appointment_id = $1;
        `, [appointment_id]);
        if (!response.rows[0] || ['done', 'cancelled'].includes(response.rows[0].status)){
            throw new Error("Appointment not in queue");
        }

        const row = response.rows[0];
        // Compute estimated_time dynamically if not stored: active_ahead * 15 min per patient
        if (!row.estimated_time) {
            const aheadMinutes = Number(row.active_ahead) * 15;
            row.estimated_time = new Date(Date.now() + aheadMinutes * 60 * 1000).toISOString();
        }

        try {
            await redis.setex(cacheKey(appointment_id), CACHE_TTL, JSON.stringify(row));
        } catch {
            console.warn("[Redis] unavailable, skipping cache write");
        }
        return row;

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
        await redis.del(cacheKey(appointment_id));
        return response.rows[0];

    }catch (e){
        console.error("Error removing from queue:", e);
        throw e;
    }
}

export async function checkIn(appointment_id: string, callerId?: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(
            `SELECT * FROM queue.queue_entries WHERE appointment_id = $1`,
            [appointment_id]
        );
        if (!rows[0]) throw new Error("Appointment not in queue");
        const entry = rows[0] as QueueEntry;

        if (callerId && entry.patient_id !== callerId) {
            throw new Error("Forbidden");
        }

        if (entry.status === "waiting") {
            // Normal check-in — patient confirmed present
            const { rows: updated } = await pool.query(`
                UPDATE queue.queue_entries SET status = 'checked_in', updated_at = NOW()
                WHERE appointment_id = $1 RETURNING *
            `, [appointment_id]);
            await redis.del(cacheKey(appointment_id));
            return updated[0] as QueueEntry;
        }

        if (entry.status === "skipped") {
            // Late arrival — rejoin at the back of the queue with a new number.
            // NEXTVAL is inlined so the sequence increment and the row update are
            // a single round-trip. The AND status = 'skipped' guard makes this
            // atomic: a concurrent check-in will match 0 rows and get an error.
            const { rows: updated } = await pool.query(`
                UPDATE queue.queue_entries
                SET status = 'waiting',
                    queue_number = CASE session
                        WHEN 'afternoon' THEN NEXTVAL('queue.queue_number_afternoon_seq')
                        ELSE NEXTVAL('queue.queue_number_morning_seq')
                    END,
                    updated_at = NOW()
                WHERE appointment_id = $1 AND status = 'skipped'
                RETURNING *
            `, [appointment_id]);
            if (!updated[0]) throw new Error("Appointment not in queue");
            await redis.del(cacheKey(appointment_id));
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
        await redis.del(cacheKey(appointment_id));
        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error marking no-show:", e);
        throw e;
    }
}

// Patient confirmed they are still coming but will be late — move to back of queue.
export async function deprioritize(appointment_id: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(`
            UPDATE queue.queue_entries
            SET status = 'waiting',
                queue_number = CASE session
                    WHEN 'afternoon' THEN NEXTVAL('queue.queue_number_afternoon_seq')
                    ELSE NEXTVAL('queue.queue_number_morning_seq')
                END,
                updated_at = NOW()
            WHERE appointment_id = $1 AND status NOT IN ('done', 'cancelled')
            RETURNING *
        `, [appointment_id]);
        if (!rows[0]) throw new Error("Appointment not in queue");
        await redis.del(cacheKey(appointment_id));
        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error deprioritizing appointment:", e);
        throw e;
    }
}

export async function completeAppointment(appointment_id: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(`
            UPDATE queue.queue_entries
            SET status = 'done', updated_at = NOW()
            WHERE appointment_id = $1 AND status NOT IN ('done', 'cancelled')
            RETURNING *
        `, [appointment_id]);
        if (!rows[0]) throw new Error("Appointment not found or cannot be completed");
        await redis.del(cacheKey(appointment_id));
        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error completing appointment:", e);
        throw e;
    }
}

export async function getCurrentCalled(doctor_id: string): Promise<QueueEntry | null> {
    const { rows } = await pool.query(`
        SELECT * FROM queue.queue_entries
        WHERE status = 'called' AND doctor_id = $1
        ORDER BY updated_at DESC
        LIMIT 1
    `, [doctor_id]);
    return rows[0] ?? null;
}

export async function callNext(session: string, doctor_id?: string): Promise<QueueEntry> {
    try {
        const { rows } = await pool.query(`
            UPDATE queue.queue_entries
            SET status = 'called', updated_at = NOW()
            WHERE id = (
                SELECT id FROM queue.queue_entries
                WHERE status = 'checked_in'
                  AND (
                      -- specific-doctor booking: patient booked this doctor
                      ($2::text IS NOT NULL AND doctor_id = $2 AND session IS NULL)
                      OR
                      -- session-based booking: no doctor preference, match by session
                      (session = $1 AND doctor_id IS NULL)
                  )
                ORDER BY queue_number ASC
                LIMIT 1
            )
            RETURNING *
        `, [session, doctor_id ?? null]);

        if (!rows[0]) throw new Error("No checked-in patients in queue");

        await redis.del(cacheKey(rows[0].appointment_id));
        return rows[0] as QueueEntry;
    } catch (e) {
        console.error("Error calling next patient:", e);
        throw e;
    }
}

export async function listActiveQueue(): Promise<QueueEntry[]> {
    const { rows } = await pool.query(`
        SELECT * FROM queue.queue_entries
        WHERE status NOT IN ('done', 'cancelled')
        ORDER BY queue_number ASC
    `);
    return rows as QueueEntry[];
}

export async function resetDailyQueue(){
    try{
        await pool.query(`DELETE FROM queue.queue_entries`);
        await pool.query(`ALTER SEQUENCE queue.queue_number_morning_seq RESTART WITH 1`);
        await pool.query(`ALTER SEQUENCE queue.queue_number_afternoon_seq RESTART WITH 1`);

        // Flush all cached queue positions via SCAN (non-blocking, O(N) spread
        // across multiple round-trips) rather than KEYS (single O(N) blocking call).
        let cursor = 0;
        do {
            const [next, keys] = await redis.scan(cursor, "MATCH", "queue:position:*", "COUNT", 100);
            cursor = parseInt(next);
            if (keys.length > 0) await redis.del(...keys);
        } while (cursor !== 0);

    }catch (e){
        console.error("Failed to reset queue:", e);
        throw e;
    }
}