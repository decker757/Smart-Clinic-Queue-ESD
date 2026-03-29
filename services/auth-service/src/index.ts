import express from "express";
import swaggerUi from "swagger-ui-express";
import { toNodeHandler } from "better-auth/node";
import { auth, trustedOrigins } from "./auth";
import { swaggerSpec } from "./swagger";

const app = express();

// Apply CORS headers to every response — BetterAuth's toNodeHandler doesn't
// add them on non-2xx responses (e.g. 422 validation errors).
app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && trustedOrigins.includes(origin)) {
        res.setHeader("Access-Control-Allow-Origin", origin);
        res.setHeader("Access-Control-Allow-Credentials", "true");
        res.setHeader("Vary", "Origin");
    }
    next();
});

// Swagger UI — must be mounted before the BetterAuth catch-all handler
app.get("/api/auth/openapi.json", (_req, res) => res.json(swaggerSpec));
app.use("/api/auth/docs", swaggerUi.serve, swaggerUi.setup(swaggerSpec));

// Handle CORS preflight for all auth routes.
app.options("/api/auth/*splat", (req, res) => {
    const origin = req.headers.origin;
    if (origin && trustedOrigins.includes(origin)) {
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        res.setHeader("Access-Control-Max-Age", "86400");
    }
    res.status(204).end();
});

app.all("/api/auth/*splat", toNodeHandler(auth));

app.listen(3000, () =>{
    console.log("Auth service running on port 3000");
})