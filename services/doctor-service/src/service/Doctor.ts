import pool from "../db/pool";

export interface Doctor {
    id: string
    name: string
    specialisation?: string
    contact?: string
    created_at: Date
}

export interface TimeSlot {
    id: string
    doctor_id: string
    start_time: Date
    end_time: Date
    status: string
}

export async function getDoctorById(doctor_id: string): Promise<Doctor> {
    const { rows } = await pool.query(
        `SELECT * FROM doctors.doctors WHERE id = $1`, [doctor_id]
    );
    if (!rows[0]) throw new Error("Doctor not found");
    return rows[0] as Doctor;
}

export async function listDoctors(): Promise<Doctor[]> {
    const { rows } = await pool.query(`SELECT * FROM doctors.doctors ORDER BY name`);
    return rows as Doctor[];
}

export async function getDoctorSlots(doctor_id: string): Promise<TimeSlot[]> {
    const { rows } = await pool.query(
        `SELECT * FROM doctors.time_slots WHERE doctor_id = $1 AND status = 'available' ORDER BY start_time`,
        [doctor_id]
    );
    return rows as TimeSlot[];
}

export async function updateSlotStatus(slot_id: string, status: string): Promise<TimeSlot> {
    const { rows } = await pool.query(
        `UPDATE doctors.time_slots SET status = $1 WHERE id = $2 RETURNING *`,
        [status, slot_id]
    );
    if (!rows[0]) throw new Error("Slot not found");
    return rows[0] as TimeSlot;
}
