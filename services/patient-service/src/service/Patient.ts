import pool from "../db/pool";

export interface Patient {
    id: string;
    phone: string | null;
    dob: string | null;
    nric: string | null;
    gender: string | null;
    allergies: string[];
    created_at: Date;
    updated_at: Date;
}

export async function getPatient(id: string): Promise<Patient | null> {
    const { rows } = await pool.query(
        `SELECT * FROM patients.patients WHERE id = $1`,
        [id]
    );
    return rows[0] ?? null;
}

export async function createPatient(id: string, data: Partial<Patient>): Promise<Patient> {
    const { rows } = await pool.query(
        `INSERT INTO patients.patients (id, phone, dob, nric, gender, allergies)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (id) DO UPDATE SET
           phone = EXCLUDED.phone,
           dob = EXCLUDED.dob,
           nric = EXCLUDED.nric,
           gender = EXCLUDED.gender,
           allergies = EXCLUDED.allergies,
           updated_at = NOW()
         RETURNING *`,
        [id, data.phone ?? null, data.dob ?? null, data.nric ?? null, data.gender ?? null, data.allergies ?? []]
    );
    return rows[0] as Patient;
}

export async function updatePatient(id: string, data: Partial<Patient>): Promise<Patient | null> {
    const { rows } = await pool.query(
        `UPDATE patients.patients
         SET phone = COALESCE($2, phone),
             dob = COALESCE($3, dob),
             nric = COALESCE($4, nric),
             gender = COALESCE($5, gender),
             allergies = COALESCE($6, allergies),
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [id, data.phone || null, data.dob || null, data.nric || null, data.gender || null, data.allergies?.length ? data.allergies : null]
    );
    return rows[0] ?? null;
}
