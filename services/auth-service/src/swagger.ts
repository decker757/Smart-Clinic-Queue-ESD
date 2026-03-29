import swaggerJsdoc from "swagger-jsdoc";

const options: swaggerJsdoc.Options = {
    definition: {
        openapi: "3.0.0",
        info: {
            title: "Auth Service",
            version: "1.0.0",
            description: "Authentication service powered by BetterAuth (RS256 JWT)",
        },
        servers: [{ url: "/api/auth" }],
        paths: {
            "/sign-in/email": {
                post: {
                    summary: "Sign in with email and password",
                    tags: ["Auth"],
                    requestBody: {
                        required: true,
                        content: {
                            "application/json": {
                                schema: {
                                    type: "object",
                                    required: ["email", "password"],
                                    properties: {
                                        email: { type: "string", format: "email" },
                                        password: { type: "string" },
                                    },
                                },
                            },
                        },
                    },
                    responses: {
                        "200": { description: "Session created, session cookie set" },
                        "401": { description: "Invalid credentials" },
                    },
                },
            },
            "/sign-up/email": {
                post: {
                    summary: "Register a new account",
                    tags: ["Auth"],
                    requestBody: {
                        required: true,
                        content: {
                            "application/json": {
                                schema: {
                                    type: "object",
                                    required: ["email", "password", "name"],
                                    properties: {
                                        email: { type: "string", format: "email" },
                                        password: { type: "string" },
                                        name: { type: "string" },
                                    },
                                },
                            },
                        },
                    },
                    responses: {
                        "200": { description: "Account created" },
                        "422": { description: "Validation error or email already in use" },
                    },
                },
            },
            "/token": {
                get: {
                    summary: "Exchange session cookie for a JWT (Bearer token)",
                    tags: ["Auth"],
                    security: [{ cookieAuth: [] }],
                    responses: {
                        "200": {
                            description: "JWT returned",
                            content: {
                                "application/json": {
                                    schema: {
                                        type: "object",
                                        properties: { token: { type: "string" } },
                                    },
                                },
                            },
                        },
                        "401": { description: "Not authenticated" },
                    },
                },
            },
            "/sign-out": {
                post: {
                    summary: "Sign out and clear session cookie",
                    tags: ["Auth"],
                    responses: {
                        "200": { description: "Signed out" },
                    },
                },
            },
            "/jwks": {
                get: {
                    summary: "Return RSA public key set (used by services to verify JWTs)",
                    tags: ["Auth"],
                    responses: {
                        "200": {
                            description: "JWKS",
                            content: {
                                "application/json": {
                                    schema: {
                                        type: "object",
                                        properties: {
                                            keys: { type: "array", items: { type: "object" } },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
        components: {
            securitySchemes: {
                cookieAuth: {
                    type: "apiKey",
                    in: "cookie",
                    name: "__Secure-better-auth.session_token",
                },
                bearerAuth: {
                    type: "http",
                    scheme: "bearer",
                    bearerFormat: "JWT",
                },
            },
        },
    },
    apis: [],
};

export const swaggerSpec = swaggerJsdoc(options);
