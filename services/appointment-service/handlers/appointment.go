package handlers

import (
	"database/sql"
	"net/http"

	"appointment-service/models"
	"github.com/gin-gonic/gin"
	_"github.com/lib/pq"
)

func GetAppointments(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		// optional filters: ?patient_id=&doctor_id=&date=2025-03-01
		patientID := c.Query("patient_id")
		doctorID := c.Query("doctor_id")
		date := c.Query("date") // expected format: YYYY-MM-DD

		// passing NULL for unused filters lets Postgres skip those conditions
		var nullPatient, nullDoctor, nullDate interface{}
		if patientID != "" {
			nullPatient = patientID
		}
		if doctorID != "" {
			nullDoctor = doctorID
		}
		if date != "" {
			nullDate = date
		}

		rows, err := db.QueryContext(c.Request.Context(), `
			SELECT id::text, patient_id::text, doctor_id::text,
				start_time, status, created_at, updated_at
			FROM appointments
			WHERE ($1::uuid IS NULL OR patient_id = $1::uuid)
			  AND ($2::uuid IS NULL OR doctor_id  = $2::uuid)
			  AND ($3::date IS NULL OR start_time::date = $3::date)
			ORDER BY start_time ASC
		`, nullPatient, nullDoctor, nullDate)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		var appts []models.Appointment
		for rows.Next() {
			var a models.Appointment
			if err := rows.Scan(&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Status, &a.CreatedAt, &a.UpdatedAt); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			appts = append(appts, a)
		}
		c.JSON(http.StatusOK, appts)
	}
}

func GetAppointment(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		var a models.Appointment
		err := db.QueryRowContext(c.Request.Context(), `
			SELECT id::text, patient_id::text, doctor_id::text,
				start_time, status, created_at, updated_at
			FROM appointments WHERE id = $1::uuid
		`, id).Scan(&a.ID, &a.PatientID, &a.DoctorID,
			&a.StartTime, &a.Status, &a.CreatedAt, &a.UpdatedAt)
		if err == sql.ErrNoRows{
			c.JSON(http.StatusNotFound, gin.H{"error": "appointment not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, a)
	}
}

func CreateAppointment(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req models.CreateAppointmentRequest
		if err := c.ShouldBindJSON(&req); err != nil{
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		// enforce 15-minute slot intervals
		if req.StartTime.Minute()%15 != 0 || req.StartTime.Second() != 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "start_time must be on a 15 minute interval"})
			return
		}

		var a models.Appointment
		err := db.QueryRowContext(c.Request.Context(), `
			INSERT INTO appointments (patient_id, doctor_id, start_time, status)
			VALUES ($1::uuid, $2::uuid, $3, $4)
			RETURNING id::text, patient_id::text, doctor_id::text,
					  start_time, status, created_at, updated_at
		`, req.PatientID, req.DoctorID, req.StartTime, models.StatusScheduled).
			Scan(&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Status, &a.CreatedAt, &a.UpdatedAt)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		} 
		c.JSON(http.StatusCreated, a)
	}
}

func UpdateAppointmentStatus(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		var req models.UpdateStatusRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		var a models.Appointment
		err := db.QueryRowContext(c.Request.Context(), `
			UPDATE appointments
			SET status = $1, updated_at = NOW()
			WHERE id = $2::uuid
			RETURNING id::text, patient_id::text, doctor_id::text,
					start_time, status, created_at, updated_at
		`, req.Status, id).
			Scan(&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Status, &a.CreatedAt, &a.UpdatedAt)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "appointment not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, a)
	}
}

// CancelAppointment is a soft delete — sets status to cancelled so history is preserved.
func CancelAppointment(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var a models.Appointment
		err := db.QueryRowContext(c.Request.Context(), `
			UPDATE appointments
			SET status = $1, updated_at = NOW()
			WHERE id = $2::uuid AND status NOT IN ('completed', 'cancelled')
			RETURNING id::text, patient_id::text, doctor_id::text,
					  start_time, status, created_at, updated_at
		`, models.StatusCancelled, id).
			Scan(&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Status, &a.CreatedAt, &a.UpdatedAt)
		if err == sql.ErrNoRows {
			// either not found, or already in a terminal state
			c.JSON(http.StatusConflict, gin.H{"error": "appointment not found or already finalised"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, a)
	}
}


