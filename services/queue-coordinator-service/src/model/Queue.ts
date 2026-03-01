/* 
This is how the queue coordinator will receive and send requests
*/

// ─── What is taken from RabbitMQ ────────────────────────
export interface AppointmentInfo {
    appointment_id: string,
    patient_id: string,
    doctor_id?: string,
    start_time?: Date,
    session?: string
}

// ─── What we put into the Queue ────────────────────────
export interface QueueEntry {
    id: string          // UUID primary key
    appointment_id: string
    patient_id: string
    doctor_id?: string
    session?: string    // morning | afternoon
    queue_number: number
    status: string      // waiting, called, in_progress, done, skipped
    created_at: Date
}