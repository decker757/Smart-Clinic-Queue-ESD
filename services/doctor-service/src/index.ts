import express, { Request, Response, NextFunction } from "express";
import doctorRouter from "./controller/Doctor";
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
app.use("/api/doctors", doctorRouter);

app.listen(config.httpPort, () => {
    console.log(`[HTTP] Doctor service running on port ${config.httpPort}`);
});

startGrpcServer();