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

export async function getDoctorSlots(doctor_id: string, date?: string): Promise<TimeSlot[]> {
    // Default to today in SGT (UTC+8) if no date provided
    const targetDate = date ?? new Date(Date.now() + 8 * 3600000).toISOString().split("T")[0];
    const { rows } = await pool.query(
        `SELECT * FROM doctors.time_slots
         WHERE doctor_id = $1 AND status = 'available' AND start_time::date = $2::date
         ORDER BY start_time`,
        [doctor_id, targetDate]
    );
    return rows as TimeSlot[];
}

export async function generateSlots(
    doctor_id: string,
    start_date: string,
    end_date: string,
): Promise<{ generated: number }> {
    const [sy, sm, sd] = start_date.split("-").map(Number);
    const [ey, em, ed] = end_date.split("-").map(Number);

    const startMs = Date.UTC(sy, sm - 1, sd);
    const endMs = Date.UTC(ey, em - 1, ed);

    // SGT session hours (subtract 8h to get UTC equivalents)
    const sessions = [
        { startH: 9, endH: 12 },   // Morning: 09:00–12:00 SGT
        { startH: 14, endH: 17 },  // Afternoon: 14:00–17:00 SGT
    ];

    const slots: { start_time: Date; end_time: Date }[] = [];
    for (let dayMs = startMs; dayMs <= endMs; dayMs += 86_400_000) {
        if (new Date(dayMs).getUTCDay() === 0) continue; // Skip Sunday
        for (const { startH, endH } of sessions) {
            for (let h = startH; h < endH; h++) {
                for (let m = 0; m < 60; m += 15) {
                    const startUTC = new Date(dayMs + (h - 8) * 3_600_000 + m * 60_000);
                    slots.push({ start_time: startUTC, end_time: new Date(startUTC.getTime() + 15 * 60_000) });
                }
            }
        }
    }

    if (slots.length === 0) return { generated: 0 };

    const values = slots.map((_, i) => `($1, $${i * 2 + 2}, $${i * 2 + 3}, 'available')`).join(", ");
    const params: (string | Date)[] = [doctor_id];
    for (const slot of slots) params.push(slot.start_time, slot.end_time);

    const result = await pool.query(
        `INSERT INTO doctors.time_slots (doctor_id, start_time, end_time, status)
         VALUES ${values}
         ON CONFLICT (doctor_id, start_time) DO NOTHING`,
        params,
    );
    return { generated: result.rowCount ?? 0 };
}

export async function updateSlotStatus(slot_id: string, status: string): Promise<TimeSlot> {
    // When marking as booked, only update if the slot is still available — prevents double-booking race
    const condition = status === "booked" ? "AND status = 'available'" : "";
    const { rows } = await pool.query(
        `UPDATE doctors.time_slots SET status = $1 WHERE id = $2 ${condition} RETURNING *`,
        [status, slot_id]
    );
    if (!rows[0]) {
        // Distinguish "not found" from "already booked" so callers can return the right status code
        const { rows: check } = await pool.query(
            `SELECT id FROM doctors.time_slots WHERE id = $1`, [slot_id]
        );
        if (!check[0]) throw new Error("Slot not found");
        throw new Error("Slot already booked");
    }
    return rows[0] as TimeSlot;
}
