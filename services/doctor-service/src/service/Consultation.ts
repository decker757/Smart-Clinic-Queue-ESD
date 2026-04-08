import pool from "../db/pool";

export interface Consultation {
    id: string;
    appointment_id: string | null;
    doctor_id: string;
    patient_id: string;
    notes: string | null;
    diagnosis: string | null;
    created_at: Date;
}

export async function createConsultation(data: {
    appointment_id?: string;
    doctor_id: string;
    patient_id: string;
    notes?: string;
    diagnosis?: string;
}): Promise<Consultation> {
    const { rows } = await pool.query(
        `INSERT INTO doctors.consultations (appointment_id, doctor_id, patient_id, notes, diagnosis)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [data.appointment_id ?? null, data.doctor_id, data.patient_id, data.notes ?? null, data.diagnosis ?? null]
    );
    return rows[0] as Consultation;
}

/**
 * Atomically claim a consultation slot as the idempotency gate.
 *
 * - First call: inserts row with completion_status='processing', returns claimed=true.
 * - Retry after failure: existing row has completion_status='failed' → resets to
 *   'processing' and returns claimed=true so the caller re-runs the flow.
 * - Retry after success: completion_status='completed' → returns cached payment_link.
 * - Concurrent duplicate: completion_status='processing' → returns claimed=false so
 *   the caller returns 409.
 */
export async function claimConsultation(
    appointment_id: string,
    doctor_id: string,
    patient_id: string,
): Promise<{ claimed: boolean; status: string; payment_link: string | null }> {
    // Attempt a fresh INSERT. ON CONFLICT DO NOTHING leaves the existing row intact.
    const { rows: inserted } = await pool.query(
        `INSERT INTO doctors.consultations (appointment_id, doctor_id, patient_id, completion_status)
         VALUES ($1, $2, $3, 'processing')
         ON CONFLICT (appointment_id) DO NOTHING
         RETURNING TRUE AS inserted`,
        [appointment_id, doctor_id, patient_id]
    );

    if (inserted.length > 0) {
        return { claimed: true, status: "processing", payment_link: null };
    }

    // Row already exists — inspect its state.
    const { rows: existing } = await pool.query(
        `SELECT completion_status, payment_link FROM doctors.consultations WHERE appointment_id = $1`,
        [appointment_id]
    );
    const row = existing[0];

    if (row.completion_status === "completed") {
        return { claimed: false, status: "completed", payment_link: row.payment_link as string | null };
    }

    if (row.completion_status === "failed") {
        // Previous attempt failed — reset so this retry can proceed.
        await pool.query(
            `UPDATE doctors.consultations SET completion_status = 'processing' WHERE appointment_id = $1`,
            [appointment_id]
        );
        return { claimed: true, status: "processing", payment_link: null };
    }

    // completion_status = 'processing' — another request is in flight.
    return { claimed: false, status: "in_progress", payment_link: null };
}

/**
 * Store consultation notes/diagnosis and mark the outbox entry as completed or failed.
 * Called at the very end of the consultation flow (on both success and failure paths).
 */
export async function finalizeConsultation(
    appointment_id: string,
    notes: string,
    diagnosis: string,
    payment_link: string | null,
    completion_status: "completed" | "failed",
): Promise<void> {
    await pool.query(
        `UPDATE doctors.consultations
         SET notes = $2, diagnosis = $3, payment_link = $4, completion_status = $5
         WHERE appointment_id = $1`,
        [appointment_id, notes || null, diagnosis || null, payment_link, completion_status]
    );
}

export async function getConsultationsByPatient(patient_id: string): Promise<Consultation[]> {
    const { rows } = await pool.query(
        `SELECT * FROM doctors.consultations WHERE patient_id = $1 ORDER BY created_at DESC`,
        [patient_id]
    );
    return rows as Consultation[];
}
