package models

import "time"

type Status string

const (
	StatusScheduled  Status = "scheduled"
	StatusCheckedIn  Status = "checked_in"
	StatusInProgress Status = "in_progress"
	StatusCompleted  Status = "completed"
	StatusCancelled  Status = "cancelled"
	StatusNoShow 	 Status = "no_show"
)

type Appointment struct {
	ID			string		`json:"id"`
	PatientID	string		`json:"patient_id"`
	DoctorID	string		`json:"doctor_id"`
	StartTime	time.Time	`json:"start_time"`
	Status		Status		`json:"status"`
	CreatedAt	time.Time	`json:"created_at"`
	UpdatedAt	time.Time	`json:"updated_at"`
}

type CreateAppointmentRequest struct {
	PatientID string	`json:"patient_id" binding:"required"`
	DoctorID  string	`json:"doctor_id"  binding:"required"`
	StartTime time.Time `json:"start_time" binding:"required"`
}

type UpdateStatusRequest struct {
	Status Status `json:"status" binding:"required"`
}