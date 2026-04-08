import swaggerJsdoc from "swagger-jsdoc";

const options: swaggerJsdoc.Options = {
    definition: {
        openapi: "3.0.0",
        info: {
            title: "Activity Log Service",
            version: "1.0.0",
            description: "Audit trail of all clinic events consumed from RabbitMQ",
        },
        servers: [{ url: "/" }],
        components: {
            securitySchemes: {
                bearerAuth: {
                    type: "http",
                    scheme: "bearer",
                    bearerFormat: "JWT",
                },
            },
            schemas: {
                ActivityLog: {
                    type: "object",
                    properties: {
                        id: { type: "string", format: "uuid" },
                        event_type: { type: "string" },
                        patient_id: { type: "string" },
                        appointment_id: { type: "string", nullable: true },
                        actor: { type: "string", nullable: true },
                        payload: { type: "object" },
                        created_at: { type: "string", format: "date-time" },
                    },
                },
            },
        },
        security: [{ bearerAuth: [] }],
        paths: {
            "/api/activity-log/patients/{id}/history": {
                get: {
                    summary: "Get all activity log entries for a patient",
                    tags: ["Activity Log"],
                    parameters: [
                        { in: "path", name: "id", required: true, schema: { type: "string" }, description: "Patient ID" },
                        { in: "query", name: "limit", schema: { type: "integer", default: 50 } },
                        { in: "query", name: "offset", schema: { type: "integer", default: 0 } },
                    ],
                    responses: {
                        "200": {
                            description: "Array of log entries",
                            content: { "application/json": { schema: { type: "array", items: { $ref: "#/components/schemas/ActivityLog" } } } },
                        },
                        "403": { description: "Forbidden" },
                    },
                },
            },
            "/api/activity-log/appointments/{id}/history": {
                get: {
                    summary: "Get full lifecycle of one appointment",
                    tags: ["Activity Log"],
                    parameters: [{ in: "path", name: "id", required: true, schema: { type: "string" }, description: "Appointment ID" }],
                    responses: {
                        "200": {
                            description: "Array of log entries for the appointment",
                            content: { "application/json": { schema: { type: "array", items: { $ref: "#/components/schemas/ActivityLog" } } } },
                        },
                        "403": { description: "Forbidden" },
                    },
                },
            },
        },
    },
    apis: [],
};

export const swaggerSpec = swaggerJsdoc(options);
