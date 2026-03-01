package handlers

import (
	"database/sql"
	"net/http"

	"appointment-service/models"
	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
)

func GetAppointments(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		patientID := c.Query("patient_id")
		doctorID := c.Query("doctor_id")
		date := c.Query("date") // expected format: YYYY-MM-DD

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
				start_time, session, estimated_time, queue_position, notes,
				status, created_at, updated_at
			FROM appointments
			WHERE ($1 IS NULL OR patient_id = $1)
			  AND ($2::uuid IS NULL OR doctor_id = $2::uuid)
			  AND ($3::date IS NULL OR start_time::date = $3::date)
			ORDER BY created_at ASC
		`, nullPatient, nullDoctor, nullDate)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		var appts []models.Appointment
		for rows.Next() {
			var a models.Appointment
			if err := rows.Scan(
				&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Session, &a.EstimatedTime, &a.QueuePosition, &a.Notes,
				&a.Status, &a.CreatedAt, &a.UpdatedAt,
			); err != nil {
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
				start_time, session, estimated_time, queue_position, notes,
				status, created_at, updated_at
			FROM appointments WHERE id = $1::uuid
		`, id).Scan(
			&a.ID, &a.PatientID, &a.DoctorID,
			&a.StartTime, &a.Session, &a.EstimatedTime, &a.QueuePosition, &a.Notes,
			&a.Status, &a.CreatedAt, &a.UpdatedAt,
		)
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

func CreateAppointment(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req models.CreateAppointmentRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		// validate booking type: must be session-based OR specific doctor, not both/neither
		if req.Session != nil && req.StartTime != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "provide either session or start_time+doctor_id, not both"})
			return
		}
		if req.Session == nil && req.StartTime == nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "provide either session (morning/afternoon) or start_time+doctor_id"})
			return
		}

		if req.Session != nil {
			// session-based booking
			if *req.Session != "morning" && *req.Session != "afternoon" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "session must be 'morning' or 'afternoon'"})
				return
			}
		} else {
			// specific doctor booking
			if req.DoctorID == nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "doctor_id is required when start_time is provided"})
				return
			}
			if req.StartTime.Minute()%15 != 0 || req.StartTime.Second() != 0 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "start_time must be on a 15 minute interval"})
				return
			}
		}

		// atomic insert with capacity check (only applies to specific doctor bookings)
		var a models.Appointment
		err := db.QueryRowContext(c.Request.Context(), `
			INSERT INTO appointments (patient_id, doctor_id, start_time, session, notes, status)
			SELECT $1, $2::uuid, $3, $4, $5, $6
			WHERE (
				$2::uuid IS NULL
				OR (
					SELECT COUNT(*)
					FROM appointments
					WHERE doctor_id = $2::uuid
					  AND start_time = $3
					  AND status NOT IN ('cancelled', 'no_show')
				) < COALESCE(
					(SELECT slot_capacity FROM doctors WHERE id = $2::uuid),
					3
				)
			)
			RETURNING id::text, patient_id::text, doctor_id::text,
					  start_time, session, estimated_time, queue_position, notes,
					  status, created_at, updated_at
		`, req.PatientID, req.DoctorID, req.StartTime, req.Session, req.Notes, models.StatusScheduled).
			Scan(
				&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Session, &a.EstimatedTime, &a.QueuePosition, &a.Notes,
				&a.Status, &a.CreatedAt, &a.UpdatedAt,
			)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusConflict, gin.H{"error": "slot is full for this doctor"})
			return
		}
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
					  start_time, session, estimated_time, queue_position, notes,
					  status, created_at, updated_at
		`, req.Status, id).
			Scan(
				&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Session, &a.EstimatedTime, &a.QueuePosition, &a.Notes,
				&a.Status, &a.CreatedAt, &a.UpdatedAt,
			)
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

func CancelAppointment(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var a models.Appointment
		err := db.QueryRowContext(c.Request.Context(), `
			UPDATE appointments
			SET status = $1, updated_at = NOW()
			WHERE id = $2::uuid AND status NOT IN ('completed', 'cancelled')
			RETURNING id::text, patient_id::text, doctor_id::text,
					  start_time, session, estimated_time, queue_position, notes,
					  status, created_at, updated_at
		`, models.StatusCancelled, id).
			Scan(
				&a.ID, &a.PatientID, &a.DoctorID,
				&a.StartTime, &a.Session, &a.EstimatedTime, &a.QueuePosition, &a.Notes,
				&a.Status, &a.CreatedAt, &a.UpdatedAt,
			)
		if err == sql.ErrNoRows {
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
