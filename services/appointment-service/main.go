package main

import (
	"log"

	"appointment-service/db"
	"appointment-service/handlers"
	"appointment-service/middleware"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)


func main(){
	_ = godotenv.Load() // loads .env for local dev; no-op in Docker

	pubKey, err := middleware.FetchPublicKey()
	if err != nil {
		log.Fatalf("failed to load auth public key: %v", err)
	}

	database := db.Connect()
	defer database.Close()

	router := gin.Default()

	appts := router.Group("/appointments", middleware.RequireAuth(pubKey))
	{
		appts.GET("",		handlers.GetAppointments(database))
		appts.POST("",		handlers.CreateAppointment(database))
		appts.GET("/:id",	handlers.GetAppointment(database))
		appts.PATCH("/:id/status",  handlers.UpdateAppointmentStatus(database))
		appts.DELETE("/:id",         handlers.CancelAppointment(database))
	}
	router.Run(":3001")
}