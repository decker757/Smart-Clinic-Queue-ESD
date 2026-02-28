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
	DoctorID      *string    `json:"doctor_id"`       // nullable - optional preference
	StartTime     time.Time  `json:"start_time"`
	EstimatedTime *time.Time `json:"estimated_time"`  // nullable - set by ETA service
	QueuePosition *int       `json:"queue_position"`  // nullable - set by queue coordinator
	Notes         *string    `json:"notes"`           // nullable
	Status        Status     `json:"status"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type CreateAppointmentRequest struct {
	PatientID string    `json:"patient_id" binding:"required"`
	DoctorID  *string   `json:"doctor_id"`
	StartTime time.Time `json:"start_time" binding:"required"`
	Notes     *string   `json:"notes"`
}

type Doctor struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Specialization string `json:"specialization"`
	SlotCapacity   int    `json:"slot_capacity"` // max patients per 15min slot, default 3
}

type UpdateStatusRequest struct {
	Status Status `json:"status" binding:"required"`
}
