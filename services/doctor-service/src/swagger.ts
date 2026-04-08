import swaggerJsdoc from "swagger-jsdoc";

const options: swaggerJsdoc.Options = {
    definition: {
        openapi: "3.0.0",
        info: {
            title: "Doctor Service",
            version: "1.0.0",
            description: "Manages doctors, time slots, and consultations",
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
                Doctor: {
                    type: "object",
                    properties: {
                        id: { type: "string" },
                        name: { type: "string" },
                        specialisation: { type: "string" },
                        contact: { type: "string" },
                        created_at: { type: "string", format: "date-time" },
                    },
                },
                TimeSlot: {
                    type: "object",
                    properties: {
                        id: { type: "string", format: "uuid" },
                        doctor_id: { type: "string" },
                        start_time: { type: "string", format: "date-time" },
                        end_time: { type: "string", format: "date-time" },
                        status: { type: "string", enum: ["available", "booked", "blocked"] },
                        created_at: { type: "string", format: "date-time" },
                    },
                },
            },
        },
        security: [{ bearerAuth: [] }],
        paths: {
            "/api/doctors": {
                get: {
                    summary: "List all doctors",
                    tags: ["Doctors"],
                    responses: {
                        "200": {
                            description: "Array of doctors",
                            content: {
                                "application/json": {
                                    schema: { type: "array", items: { $ref: "#/components/schemas/Doctor" } },
                                },
                            },
                        },
                    },
                },
            },
            "/api/doctors/{id}": {
                get: {
                    summary: "Get a doctor by ID",
                    tags: ["Doctors"],
                    parameters: [{ in: "path", name: "id", required: true, schema: { type: "string" } }],
                    responses: {
                        "200": { description: "Doctor object", content: { "application/json": { schema: { $ref: "#/components/schemas/Doctor" } } } },
                        "404": { description: "Doctor not found" },
                    },
                },
            },
            "/api/doctors/{id}/slots": {
                get: {
                    summary: "Get available slots for a doctor",
                    tags: ["Slots"],
                    parameters: [
                        { in: "path", name: "id", required: true, schema: { type: "string" } },
                        { in: "query", name: "date", schema: { type: "string", format: "date" }, description: "Filter by date (YYYY-MM-DD)" },
                    ],
                    responses: {
                        "200": {
                            description: "Array of time slots",
                            content: { "application/json": { schema: { type: "array", items: { $ref: "#/components/schemas/TimeSlot" } } } },
                        },
                    },
                },
            },
            "/api/doctors/{id}/slots/generate": {
                post: {
                    summary: "Generate 15-min slots for a doctor over a date range",
                    tags: ["Slots"],
                    parameters: [{ in: "path", name: "id", required: true, schema: { type: "string" } }],
                    requestBody: {
                        required: true,
                        content: {
                            "application/json": {
                                schema: {
                                    type: "object",
                                    required: ["start_date", "end_date"],
                                    properties: {
                                        start_date: { type: "string", format: "date" },
                                        end_date: { type: "string", format: "date" },
                                    },
                                },
                            },
                        },
                    },
                    responses: {
                        "201": { description: "Slots generated" },
                        "400": { description: "start_date and end_date are required" },
                    },
                },
            },
            "/api/doctors/slots/{slot_id}": {
                patch: {
                    summary: "Update slot status (available / booked / blocked)",
                    tags: ["Slots"],
                    parameters: [{ in: "path", name: "slot_id", required: true, schema: { type: "string", format: "uuid" } }],
                    requestBody: {
                        required: true,
                        content: {
                            "application/json": {
                                schema: {
                                    type: "object",
                                    required: ["status"],
                                    properties: {
                                        status: { type: "string", enum: ["available", "booked", "blocked"] },
                                    },
                                },
                            },
                        },
                    },
                    responses: {
                        "200": { description: "Updated slot" },
                        "400": { description: "Invalid status" },
                        "404": { description: "Slot not found" },
                        "409": { description: "Slot already booked" },
                    },
                },
            },
        },
    },
    apis: [],
};

export const swaggerSpec = swaggerJsdoc(options);
