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

export async function getConsultationsByPatient(patient_id: string): Promise<Consultation[]> {
    const { rows } = await pool.query(
        `SELECT * FROM doctors.consultations WHERE patient_id = $1 ORDER BY created_at DESC`,
        [patient_id]
    );
    return rows as Consultation[];
}
