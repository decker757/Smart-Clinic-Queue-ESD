package db

import (
	"database/sql"
	"log"
	"os"
)

func Connect() *sql.DB {
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		log.Fatal("DATABASE_URL is not set")
	}
	conn, err := sql.Open("postgres", url)
	if err != nil {
		log.Fatalf("failed to open db: %v", err)
	}
	if err := conn.Ping(); err != nil {
		log.Fatalf("failed to connect to db: %v", err)
	}
	log.Println("connected to database")
	return conn
}