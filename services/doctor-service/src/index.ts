import express, { Request, Response, NextFunction } from "express";
import doctorRouter from "./controller/Doctor";
import consultationRouter from "./controller/Consultation";
import mcRouter from "./controller/MC";
import patientRouter from "./controller/Patient";
import { startGrpcServer } from "./grpc";
import { config } from "./config";

const app = express();

app.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") { res.status(204).end(); return; }
    next();
});

app.use(express.json());
app.get("/health", (_req, res) => res.json({ status: "ok", service: "doctor-service" }));
app.use("/api/doctors", doctorRouter);
app.use("/api/doctors/consultations", consultationRouter);
app.use("/api/doctors/mc", mcRouter);
app.use("/api/doctors/patients", patientRouter);

app.listen(config.httpPort, () => {
    console.log(`[HTTP] Doctor service running on port ${config.httpPort}`);
});

startGrpcServer();
