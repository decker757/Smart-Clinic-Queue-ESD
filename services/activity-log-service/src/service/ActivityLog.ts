/**
 * Activity Log business logic
 *
 * - recordEvent: inserts an event into the activity_log.logs table
 * - getPatientHistory: fetches all events for a given patient
 * - getAppointmentHistory: fetches all events for a given appointment
 */

import { ClinicEvent, ActivityLogEntry } from "../model/ActivityLog";
import pool from "../db/db";

export async function recordEvent(event: ClinicEvent): Promise<ActivityLogEntry> {
    const { rows } = await pool.query(
        `INSERT INTO activity_log.logs (event_type, patient_id, appointment_id, actor, payload)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [
            event.event_type,
            event.patient_id,
            event.appointment_id ?? null,
            event.actor ?? "system",
            JSON.stringify(event.payload),
        ]
    );
    return rows[0] as ActivityLogEntry;
}

export async function getPatientHistory(
    patient_id: string,
    limit: number = 50,
    offset: number = 0
): Promise<ActivityLogEntry[]> {
    const { rows } = await pool.query(
        `SELECT * FROM activity_log.logs
         WHERE patient_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [patient_id, limit, offset]
    );
    return rows as ActivityLogEntry[];
}

export async function getAppointmentHistory(
    appointment_id: string,
    patient_id: string
): Promise<ActivityLogEntry[]> {
    const { rows } = await pool.query(
        `SELECT * FROM activity_log.logs
         WHERE appointment_id = $1 AND patient_id = $2
         ORDER BY created_at ASC`,
        [appointment_id, patient_id]
    );
    return rows as ActivityLogEntry[];
}
