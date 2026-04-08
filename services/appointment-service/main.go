package main

import (
	"log"
	"net/http"

	"appointment-service/db"
	"appointment-service/docs"
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

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "appointment-service"})
	})
	router.GET("/appointments/docs", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(docs.SwaggerHTML))
	})
	router.GET("/appointments/openapi.json", func(c *gin.Context) {
		c.Data(http.StatusOK, "application/json", []byte(docs.SwaggerJSON))
	})

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