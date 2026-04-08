import pool from "../db/pool";
import { uploadFile } from "../storage/supabase";

export interface Memo {
    id: string;
    patient_id: string;
    title: string;
    content: string | null;
    file_url: string | null;
    file_type: string | null;
    record_type: "memo" | "mc" | "prescription";
    issued_by: string | null;
    appointment_id: string | null;
    created_at: Date;
}

export async function getMemos(patient_id: string): Promise<Memo[]> {
    const { rows } = await pool.query(
        `SELECT * FROM patients.memos
         WHERE patient_id = $1
         ORDER BY created_at DESC`,
        [patient_id]
    );
    return rows as Memo[];
}

// Called by consultation composite to store doctor-issued MC or prescription
export async function createDoctorRecord(
    patient_id: string,
    title: string,
    content: string,
    record_type: "mc" | "prescription",
    issued_by: string,
    appointment_id?: string
): Promise<Memo> {
    // Ensure patient row exists (BetterAuth users may not have been explicitly registered)
    await pool.query(
        `INSERT INTO patients.patients (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`,
        [patient_id]
    );
    // ON CONFLICT: if an MC or prescription already exists for this appointment,
    // return the existing row unchanged so that consultation completion retries
    // cannot create duplicate records.
    const { rows } = await pool.query(
        `INSERT INTO patients.memos (patient_id, title, content, record_type, issued_by, appointment_id)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (appointment_id, record_type) WHERE appointment_id IS NOT NULL
         DO UPDATE SET issued_by = EXCLUDED.issued_by
         RETURNING *`,
        [patient_id, title, content, record_type, issued_by, appointment_id ?? null]
    );
    return rows[0] as Memo;
}

export async function createTextMemo(
    patient_id: string,
    title: string,
    content: string
): Promise<Memo> {
    await pool.query(
        `INSERT INTO patients.patients (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`,
        [patient_id]
    );
    const { rows } = await pool.query(
        `INSERT INTO patients.memos (patient_id, title, content)
         VALUES ($1, $2, $3)
         RETURNING *`,
        [patient_id, title, content]
    );
    return rows[0] as Memo;
}

export async function createFileMemo(
    patient_id: string,
    title: string,
    file: Express.Multer.File
): Promise<Memo> {
    await pool.query(
        `INSERT INTO patients.patients (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`,
        [patient_id]
    );
    const fileUrl = await uploadFile(patient_id, file.originalname, file.buffer, file.mimetype);
    const fileType = file.mimetype.split("/")[1];

    const { rows } = await pool.query(
        `INSERT INTO patients.memos (patient_id, title, file_url, file_type)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [patient_id, title, fileUrl, fileType]
    );
    return rows[0] as Memo;
}
