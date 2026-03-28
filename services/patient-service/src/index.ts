import express, { Request, Response, NextFunction } from "express";
import patientRouter from "./controller/Patient";
import historyRouter from "./controller/History";
import memoRouter from "./controller/Memo";
import { startGrpcServer } from "./grpc";
import { fetchPublicKey } from "./middleware/auth";

const app = express();

app.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") { res.status(204).end(); return; }
    next();
});

app.use(express.json());

app.get("/health", (_req: Request, res: Response) => {
    res.json({ status: "ok", service: "patient-service" });
});

app.use("/api/patients", patientRouter);
app.use("/api/patients/:id/history", historyRouter);
app.use("/api/patients/:id/memos", memoRouter);

const PORT = process.env.PORT ?? "3007";

startGrpcServer();
app.listen(PORT, () => console.log(`[HTTP] Patient service on :${PORT}`));

fetchPublicKey().catch((err) => {
    console.error("[Auth] Failed to fetch public key:", err);
});
