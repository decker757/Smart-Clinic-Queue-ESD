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
    queue_number: number       // display-only, never changes after assignment
    sort_key: number           // ordering column for callNext; queue_number * 1000 initially
    status: string             // waiting, called, in_progress, done, skipped
    estimated_time?: Date      // set by ETA service
    estimated_arrival_at?: Date // set on check-in; overridden for late specific-booking patients
    created_at: Date
    updated_at: Date
}