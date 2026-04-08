package docs

// OpenAPI 3.0 spec for the appointment-service.
// Served at GET /appointments/openapi.json
// Swagger UI at GET /appointments/docs
const SwaggerJSON = `{
  "openapi": "3.0.0",
  "info": {
    "title": "Appointment Service",
    "version": "1.0.0",
    "description": "Manages appointment booking, status updates, and cancellations"
  },
  "servers": [{ "url": "/" }],
  "components": {
    "securitySchemes": {
      "bearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT"
      }
    },
    "schemas": {
      "Appointment": {
        "type": "object",
        "properties": {
          "id":             { "type": "string", "format": "uuid" },
          "patient_id":     { "type": "string" },
          "doctor_id":      { "type": "string", "nullable": true },
          "start_time":     { "type": "string", "format": "date-time", "nullable": true },
          "session":        { "type": "string", "enum": ["morning","afternoon"], "nullable": true },
          "estimated_time": { "type": "string", "format": "date-time", "nullable": true },
          "queue_position": { "type": "integer", "nullable": true },
          "notes":          { "type": "string", "nullable": true },
          "status":         { "type": "string", "enum": ["scheduled","checked_in","in_progress","completed","cancelled","no_show"] },
          "created_at":     { "type": "string", "format": "date-time" },
          "updated_at":     { "type": "string", "format": "date-time" }
        }
      }
    }
  },
  "security": [{ "bearerAuth": [] }],
  "paths": {
    "/appointments": {
      "get": {
        "summary": "List appointments",
        "tags": ["Appointments"],
        "parameters": [
          { "in": "query", "name": "patient_id", "schema": { "type": "string" }, "description": "Filter by patient ID" },
          { "in": "query", "name": "doctor_id",  "schema": { "type": "string" }, "description": "Filter by doctor ID" },
          { "in": "query", "name": "date",        "schema": { "type": "string", "format": "date" }, "description": "Filter by date (YYYY-MM-DD)" }
        ],
        "responses": {
          "200": {
            "description": "Array of appointments",
            "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Appointment" } } } }
          }
        }
      },
      "post": {
        "summary": "Create an appointment",
        "tags": ["Appointments"],
        "description": "Provide either 'session' (morning/afternoon) for generic booking, or 'start_time' + 'doctor_id' for a specific slot.",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": ["patient_id"],
                "properties": {
                  "patient_id": { "type": "string" },
                  "doctor_id":  { "type": "string", "nullable": true },
                  "start_time": { "type": "string", "format": "date-time", "nullable": true },
                  "session":    { "type": "string", "enum": ["morning","afternoon"], "nullable": true },
                  "notes":      { "type": "string", "nullable": true }
                }
              }
            }
          }
        },
        "responses": {
          "201": { "description": "Appointment created", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Appointment" } } } },
          "400": { "description": "Validation error" },
          "409": { "description": "Slot full for this doctor" }
        }
      }
    },
    "/appointments/{id}": {
      "get": {
        "summary": "Get one appointment by ID",
        "tags": ["Appointments"],
        "parameters": [{ "in": "path", "name": "id", "required": true, "schema": { "type": "string", "format": "uuid" } }],
        "responses": {
          "200": { "description": "Appointment object", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Appointment" } } } },
          "404": { "description": "Appointment not found" }
        }
      },
      "delete": {
        "summary": "Cancel an appointment",
        "tags": ["Appointments"],
        "parameters": [{ "in": "path", "name": "id", "required": true, "schema": { "type": "string", "format": "uuid" } }],
        "responses": {
          "200": { "description": "Cancelled appointment" },
          "409": { "description": "Appointment not found or already finalised" }
        }
      }
    },
    "/appointments/{id}/status": {
      "patch": {
        "summary": "Update appointment status",
        "tags": ["Appointments"],
        "parameters": [{ "in": "path", "name": "id", "required": true, "schema": { "type": "string", "format": "uuid" } }],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": ["status"],
                "properties": {
                  "status": { "type": "string", "enum": ["scheduled","checked_in","in_progress","completed","cancelled","no_show"] }
                }
              }
            }
          }
        },
        "responses": {
          "200": { "description": "Updated appointment" },
          "400": { "description": "Invalid status" },
          "404": { "description": "Appointment not found" }
        }
      }
    }
  }
}`

// SwaggerHTML is the swagger-ui page that loads the spec from /appointments/openapi.json.
const SwaggerHTML = `<!DOCTYPE html>
<html>
<head>
  <title>Appointment Service — API Docs</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>
  SwaggerUIBundle({
    url: "/appointments/openapi.json",
    dom_id: '#swagger-ui',
    presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
    layout: "BaseLayout"
  })
</script>
</body>
</html>`
