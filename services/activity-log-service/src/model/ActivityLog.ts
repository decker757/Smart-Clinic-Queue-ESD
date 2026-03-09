/**
 * Activity Log data models
 *
 * These define what goes INTO the DB and what comes OUT via REST.
 */

// ─── What we receive from RabbitMQ ──────────────────────────
export interface ClinicEvent {
    event_type: string;         // routing key, e.g. "appointment.booked"
    patient_id: string;
    appointment_id?: string;
    actor?: string;             // "patient", "staff", "system"
    payload: Record<string, any>;  // full raw event body
}

// ─── What we store / return from the DB ─────────────────────
export interface ActivityLogEntry {
    id: string;
    event_type: string;
    patient_id: string;
    appointment_id: string | null;
    actor: string | null;
    payload: Record<string, any>;
    created_at: Date;
}
