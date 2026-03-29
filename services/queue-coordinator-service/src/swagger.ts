import swaggerJsdoc from "swagger-jsdoc";

const options: swaggerJsdoc.Options = {
    definition: {
        openapi: "3.0.0",
        info: {
            title: "Queue Coordinator Service",
            version: "1.0.0",
            description: "Manages clinic queue: check-in, call-next, deprioritize, and real-time WebSocket updates",
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
                QueueEntry: {
                    type: "object",
                    properties: {
                        id: { type: "string", format: "uuid" },
                        appointment_id: { type: "string" },
                        patient_id: { type: "string" },
                        doctor_id: { type: "string" },
                        session: { type: "string", enum: ["morning", "afternoon"] },
                        queue_number: { type: "integer" },
                        status: {
                            type: "string",
                            enum: ["waiting", "checked_in", "called", "in_progress", "done", "skipped", "cancelled"],
                        },
                        estimated_time: { type: "string", format: "date-time", nullable: true },
                        created_at: { type: "string", format: "date-time" },
                        updated_at: { type: "string", format: "date-time" },
                    },
                },
            },
        },
        security: [{ bearerAuth: [] }],
        paths: {
            "/api/queue/active": {
                get: {
                    summary: "List all active queue entries (staff view)",
                    tags: ["Queue"],
                    responses: {
                        "200": {
                            description: "Array of active queue entries",
                            content: { "application/json": { schema: { type: "array", items: { $ref: "#/components/schemas/QueueEntry" } } } },
                        },
                    },
                },
            },
            "/api/queue/position/{appointment_id}": {
                get: {
                    summary: "Get queue position for a patient's appointment",
                    tags: ["Queue"],
                    parameters: [{ in: "path", name: "appointment_id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Queue position info" },
                        "403": { description: "Forbidden" },
                        "404": { description: "Appointment not in queue" },
                    },
                },
            },
            "/api/queue/checkin/{appointment_id}": {
                post: {
                    summary: "Patient confirms arrival (check-in)",
                    tags: ["Queue"],
                    parameters: [{ in: "path", name: "appointment_id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Updated queue entry", content: { "application/json": { schema: { $ref: "#/components/schemas/QueueEntry" } } } },
                        "403": { description: "Forbidden" },
                        "404": { description: "Appointment not in queue" },
                        "409": { description: "Cannot check in at this status" },
                    },
                },
            },
            "/api/queue/call-next": {
                post: {
                    summary: "Call the next patient (doctor action)",
                    tags: ["Queue"],
                    requestBody: {
                        required: true,
                        content: {
                            "application/json": {
                                schema: {
                                    type: "object",
                                    properties: {
                                        session: { type: "string", enum: ["morning", "afternoon"] },
                                        doctor_id: { type: "string" },
                                    },
                                },
                            },
                        },
                    },
                    responses: {
                        "200": { description: "Called queue entry" },
                        "400": { description: "Must provide session or doctor_id" },
                        "404": { description: "No waiting patients in queue" },
                    },
                },
            },
            "/api/queue/complete/{appointment_id}": {
                post: {
                    summary: "Doctor marks consultation as complete",
                    tags: ["Queue"],
                    parameters: [{ in: "path", name: "appointment_id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Completed queue entry" },
                        "404": { description: "Appointment not found or cannot be completed" },
                    },
                },
            },
            "/api/queue/no-show/{appointment_id}": {
                post: {
                    summary: "Mark patient as no-show",
                    tags: ["Queue"],
                    parameters: [{ in: "path", name: "appointment_id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Updated queue entry" },
                        "404": { description: "Appointment not found or already resolved" },
                    },
                },
            },
            "/api/queue/deprioritize/{appointment_id}": {
                post: {
                    summary: "Move patient to back of queue (late arrival penalty)",
                    tags: ["Queue"],
                    parameters: [{ in: "path", name: "appointment_id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Deprioritized entry" },
                        "404": { description: "Appointment not in queue" },
                    },
                },
            },
            "/api/queue/current/{doctor_id}": {
                get: {
                    summary: "Get currently called patient for a doctor",
                    tags: ["Queue"],
                    parameters: [{ in: "path", name: "doctor_id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Current queue entry" },
                        "404": { description: "No current patient" },
                    },
                },
            },
            "/api/queue/reset": {
                post: {
                    summary: "Reset queue at start of day",
                    tags: ["Queue"],
                    responses: {
                        "200": { description: "Queue reset successfully" },
                    },
                },
            },
        },
    },
    apis: [],
};

export const swaggerSpec = swaggerJsdoc(options);
