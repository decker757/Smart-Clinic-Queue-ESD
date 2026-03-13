import pool from "../db/pool";

export interface MedicalCertificate {
    id: string;
    appointment_id: string | null;
    doctor_id: string;
    patient_id: string;
    start_date: string;
    end_date: string;
    reason: string | null;
    created_at: Date;
}

export async function issueMC(data: {
    appointment_id?: string;
    doctor_id: string;
    patient_id: string;
    start_date: string;
    end_date: string;
    reason?: string;
}): Promise<MedicalCertificate> {
    const { rows } = await pool.query(
        `INSERT INTO doctors.medical_certificates (appointment_id, doctor_id, patient_id, start_date, end_date, reason)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [data.appointment_id ?? null, data.doctor_id, data.patient_id, data.start_date, data.end_date, data.reason ?? null]
    );
    return rows[0] as MedicalCertificate;
}

export async function getMCsByPatient(patient_id: string): Promise<MedicalCertificate[]> {
    const { rows } = await pool.query(
        `SELECT * FROM doctors.medical_certificates WHERE patient_id = $1 ORDER BY created_at DESC`,
        [patient_id]
    );
    return rows as MedicalCertificate[];
}
