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
            WITH seq AS (SELECT NEXTVAL('queue.${sequenceName}') AS qn)
            INSERT INTO queue.queue_entries (appointment_id, patient_id, doctor_id, session, queue_number, sort_key, status)
            SELECT $1, $2, $3, $4, seq.qn, seq.qn * 1000, 'waiting'
            FROM seq
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
            SELECT e.queue_number, e.sort_key, e.estimated_time, e.status, e.doctor_id, e.session,
                   (SELECT COUNT(*) FROM queue.queue_entries a
                    WHERE a.sort_key < e.sort_key
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
                UPDATE queue.queue_entries
                SET status = 'checked_in',
                    estimated_arrival_at = NOW(),
                    updated_at = NOW()
                WHERE appointment_id = $1 RETURNING *
            `, [appointment_id]);
            await redis.del(cacheKey(appointment_id));
            return updated[0] as QueueEntry;
        }

        if (entry.status === "skipped") {
            // Late arrival — rejoin at the back of the queue with a new number.
            // CTE ensures the NEXTVAL and the UPDATE are a single round-trip.
            // sort_key is also reset to new_qn * 1000 so ordering stays consistent.
            const { rows: updated } = await pool.query(`
                WITH new_num AS (
                    SELECT CASE (SELECT session FROM queue.queue_entries WHERE appointment_id = $1)
                        WHEN 'afternoon' THEN NEXTVAL('queue.queue_number_afternoon_seq')
                        ELSE NEXTVAL('queue.queue_number_morning_seq')
                    END AS qn
                )
                UPDATE queue.queue_entries
                SET status = 'waiting',
                    queue_number = (SELECT qn FROM new_num),
                    sort_key = (SELECT qn FROM new_num) * 1000,
                    estimated_arrival_at = NOW(),
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

// Patient confirmed they are still coming but will be late.
//
// Generic queue patients: shift back by ceil(travel_eta_minutes / 15) slot bands
// using sort_key midpoint insertion. queue_number (display) is unchanged.
//
// Specific booking patients: set estimated_arrival_at = NOW() + travel_eta so
// callNext withholds their tier-0 slot until they physically arrive.
export async function deprioritize(appointment_id: string, travel_eta_minutes: number = 0): Promise<QueueEntry> {
    try {
        const { rows: entryRows } = await pool.query(
            `SELECT * FROM queue.queue_entries WHERE appointment_id = $1`,
            [appointment_id]
        );
        if (!entryRows[0]) throw new Error("Appointment not in queue");
        const current = entryRows[0];
        if (['done', 'cancelled'].includes(current.status)) throw new Error("Appointment not in queue");

        let updated: any;

        if (current.session !== null && current.session !== undefined) {
            // ── Generic queue patient: slot-band shift ──────────────────────────
            const slots_to_shift = Math.max(1, Math.ceil(travel_eta_minutes / 15));

            // All active generic entries for this session ordered by sort_key
            const { rows: peers } = await pool.query(`
                SELECT sort_key FROM queue.queue_entries
                WHERE session = $1
                  AND doctor_id IS NULL
                  AND status NOT IN ('done', 'cancelled')
                ORDER BY sort_key ASC
            `, [current.session]);

            const currentPos = peers.findIndex((r: any) => Number(r.sort_key) === Number(current.sort_key));
            const targetPos = Math.min(
                currentPos === -1 ? peers.length - 1 : currentPos + slots_to_shift,
                peers.length - 1
            );

            let newSortKey: number;
            if (peers.length === 0 || targetPos >= peers.length - 1) {
                // Place at end
                const last = peers[peers.length - 1];
                newSortKey = (last ? Number(last.sort_key) : Number(current.sort_key)) + 1000;
            } else {
                const targetSortKey = Number(peers[targetPos].sort_key);
                const nextSortKey   = Number(peers[targetPos + 1].sort_key);
                newSortKey = targetSortKey + Math.floor((nextSortKey - targetSortKey) / 2);
            }

            const { rows } = await pool.query(`
                UPDATE queue.queue_entries
                SET status = 'checked_in',
                    sort_key = $2,
                    estimated_arrival_at = NOW(),
                    updated_at = NOW()
                WHERE appointment_id = $1 AND status NOT IN ('done', 'cancelled')
                RETURNING *
            `, [appointment_id, newSortKey]);
            updated = rows[0];
        } else {
            // ── Specific booking patient: defer tier-0 until arrival ────────────
            const { rows } = await pool.query(`
                UPDATE queue.queue_entries
                SET status = 'checked_in',
                    estimated_arrival_at = NOW() + ($2 * INTERVAL '1 minute'),
                    updated_at = NOW()
                WHERE appointment_id = $1 AND status NOT IN ('done', 'cancelled')
                RETURNING *
            `, [appointment_id, travel_eta_minutes]);
            updated = rows[0];
        }

        if (!updated) throw new Error("Appointment not in queue");
        await redis.del(cacheKey(appointment_id));
        return updated as QueueEntry;
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
            SET status    = 'called',
                doctor_id = COALESCE(doctor_id, $2),
                updated_at = NOW()
            WHERE id = (
                SELECT qe.id
                FROM queue.queue_entries qe
                INNER JOIN appointments.appointments a
                    ON a.id = qe.appointment_id::uuid
                WHERE qe.status = 'checked_in'
                  AND (
                      -- specific booking for this doctor
                      ($2::text IS NOT NULL AND qe.doctor_id = $2 AND qe.session IS NULL)
                      OR
                      -- generic queue patient (no doctor preference)
                      (qe.session = $1 AND qe.doctor_id IS NULL)
                  )
                ORDER BY
                  CASE
                    -- Tier 0: specific booking due AND patient has arrived (or no ETA override)
                    WHEN qe.doctor_id = $2
                      AND a.start_time <= NOW()
                      AND (qe.estimated_arrival_at IS NULL OR qe.estimated_arrival_at <= NOW())
                    THEN 0

                    -- Tier 1: generic patient — but only if the current 15-min slot has no
                    -- checked-in specific booking waiting to be seen.
                    -- If doctor_id is NULL (session-based call) skip the slot-protection check.
                    WHEN qe.doctor_id IS NULL
                      AND (
                        $2::text IS NULL
                        OR NOT EXISTS (
                          SELECT 1
                          FROM queue.queue_entries qe2
                          INNER JOIN appointments.appointments a2
                              ON a2.id = qe2.appointment_id::uuid
                          WHERE qe2.doctor_id = $2
                            AND qe2.status = 'checked_in'
                            AND a2.start_time = date_trunc('hour', NOW())
                                + (FLOOR(EXTRACT(minute FROM NOW()) / 15) * INTERVAL '15 minutes')
                        )
                      )
                    THEN 1

                    -- Tier 2: everything else (specific not yet due, or generic blocked by slot)
                    ELSE 2
                  END ASC,
                  -- Within each tier: generic patients ordered by slot-band (sort_key);
                  -- specific patients ordered by sort_key which equals queue_number * 1000
                  qe.sort_key ASC
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

// Mark that we've sent the "approaching" notification so we don't re-fire on the next tick.
export async function markApproachingNotified(appointment_id: string): Promise<void> {
    await pool.query(`
        UPDATE queue.queue_entries
        SET approaching_notified_at = NOW()
        WHERE appointment_id = $1 AND status = 'waiting' AND approaching_notified_at IS NULL
    `, [appointment_id]);
}

// Remove a patient only if they're still waiting (haven't checked in during the TTL window).
export async function removeIfWaiting(appointment_id: string): Promise<QueueEntry | null> {
    const { rows } = await pool.query(`
        UPDATE queue.queue_entries SET status = 'cancelled', updated_at = NOW()
        WHERE appointment_id = $1 AND status = 'waiting'
        RETURNING *
    `, [appointment_id]);
    if (rows[0]) await redis.del(cacheKey(appointment_id));
    return rows[0] ?? null;
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