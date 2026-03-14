import express, { Request, Response, NextFunction } from "express";
import doctorRouter from "./controller/Doctor";
import consultationRouter from "./controller/Consultation";
import { startGrpcServer } from "./grpc";
import { config } from "./config";
import { fetchPublicKey, requireAuth } from "./middleware/auth";

const app = express();

app.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") { res.status(204).end(); return; }
    next();
});

app.use(express.json());
app.get("/health", (_req: Request, res: Response) => res.json({ status: "ok", service: "doctor-service" }));

app.use("/api/doctors", requireAuth, doctorRouter);
app.use("/api/doctors/consultations", requireAuth, consultationRouter);

async function main() {
    await fetchPublicKey();
    app.listen(config.httpPort, () => {
        console.log(`[HTTP] Doctor service running on port ${config.httpPort}`);
    });
    startGrpcServer();
}

main().catch((err) => {
    console.error("[Startup] Fatal:", err);
    process.exit(1);
});
