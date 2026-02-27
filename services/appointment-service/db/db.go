package db

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"fmt"
	"log"
	"os"

	"github.com/lib/pq"
)

// schemaConnector wraps pq.Connector and runs SET search_path on every new connection,
// so all queries from the pool land in the right schema regardless of the URL options.
type schemaConnector struct {
	*pq.Connector
	schema string
}

func (sc *schemaConnector) Connect(ctx context.Context) (driver.Conn, error) {
	conn, err := sc.Connector.Connect(ctx)
	if err != nil {
		return nil, err
	}
	stmt, err := conn.Prepare(fmt.Sprintf("SET search_path TO %s", sc.schema))
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to prepare SET search_path: %w", err)
	}
	defer stmt.Close()
	if _, err := stmt.Exec([]driver.Value{}); err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to set search_path: %w", err)
	}
	return conn, nil
}

func Connect() *sql.DB {
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		log.Fatal("DATABASE_URL is not set")
	}
	connector, err := pq.NewConnector(url)
	if err != nil {
		log.Fatalf("failed to create db connector: %v", err)
	}
	db := sql.OpenDB(&schemaConnector{Connector: connector, schema: "appointments"})
	if err := db.Ping(); err != nil {
		log.Fatalf("failed to connect to db: %v", err)
	}
	log.Println("connected to database")
	return db
}
