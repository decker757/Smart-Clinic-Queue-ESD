package models

import "time"

type Status string

const (
	StatusScheduled  Status = "scheduled"
	StatusCheckedIn  Status = "checked_in"
	StatusInProgress Status = "in_progress"
	StatusCompleted  Status = "completed"
	StatusCancelled  Status = "cancelled"
	StatusNoShow     Status = "no_show"
)

type Appointment struct {
	ID            string     `json:"id"`
	PatientID     string     `json:"patient_id"`
	DoctorID      *string    `json:"doctor_id"`      // null for session-based bookings
	StartTime     *time.Time `json:"start_time"`     // null for session-based bookings
	Session       *string    `json:"session"`        // "morning" | "afternoon" | null
	EstimatedTime *time.Time `json:"estimated_time"` // set by ETA service
	QueuePosition *int       `json:"queue_position"` // set by queue coordinator
	Notes         *string    `json:"notes"`
	Status        Status     `json:"status"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type CreateAppointmentRequest struct {
	PatientID string     `json:"patient_id" binding:"required"`
	DoctorID  *string    `json:"doctor_id"`
	StartTime *time.Time `json:"start_time"` // required for specific doctor bookings
	Session   *string    `json:"session"`    // required for generic bookings: "morning" | "afternoon"
	Notes     *string    `json:"notes"`
}

type Doctor struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Specialization string `json:"specialization"`
	SlotCapacity   int    `json:"slot_capacity"`
}

type UpdateStatusRequest struct {
	Status Status `json:"status" binding:"required"`
}
