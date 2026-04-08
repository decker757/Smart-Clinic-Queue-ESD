import pool from "../db/pool";

export interface MedicalHistory {
    id: string;
    patient_id: string;
    diagnosis: string;
    diagnosed_at: string | null;
    notes: string | null;
    created_at: Date;
}

export async function getHistory(patient_id: string): Promise<MedicalHistory[]> {
    const { rows } = await pool.query(
        `SELECT * FROM patients.medical_history
         WHERE patient_id = $1
         ORDER BY created_at DESC`,
        [patient_id]
    );
    return rows as MedicalHistory[];
}

export async function addHistory(
    patient_id: string,
    data: { diagnosis: string; diagnosed_at?: string; notes?: string; appointment_id?: string }
): Promise<MedicalHistory> {
    await pool.query(
        `INSERT INTO patients.patients (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`,
        [patient_id]
    );
    // ON CONFLICT: if a history entry already exists for this appointment,
    // return the existing row so consultation completion retries are idempotent.
    const { rows } = await pool.query(
        `INSERT INTO patients.medical_history (patient_id, diagnosis, diagnosed_at, notes, appointment_id)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (appointment_id) WHERE appointment_id IS NOT NULL
         DO UPDATE SET diagnosis = EXCLUDED.diagnosis
         RETURNING *`,
        [patient_id, data.diagnosis, data.diagnosed_at ?? null, data.notes ?? null, data.appointment_id ?? null]
    );
    return rows[0] as MedicalHistory;
}
