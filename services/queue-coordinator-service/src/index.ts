import http from "http";
import express, { Request, Response, NextFunction } from "express";
import swaggerUi from "swagger-ui-express";
import cron from "node-cron";
import queueRouter from "./controller/Queue";
import { startConsumer } from "./consumer/rabbitmq";
import { createWsServer } from "./ws/manager";
import { startGrpcServer } from "./grpc";
import { resetDailyQueue } from "./service/Queue";
import { swaggerSpec } from "./swagger";

const app = express();

// CORS — allow all origins (Authorization header is explicitly permissioned)
app.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
        res.status(204).end();
        return;
    }
    next();
});

app.use(express.json());
app.get("/api/queue/openapi.json", (_req: Request, res: Response) => res.json(swaggerSpec));
app.use("/api/queue/docs", swaggerUi.serve, swaggerUi.setup(swaggerSpec));
app.use("/api/queue", queueRouter);

const PORT = parseInt(process.env.PORT || "3002");

const server = http.createServer(app);
createWsServer(server);

server.listen(PORT, () => {
    console.log(`Queue coordinator service running on port ${PORT}`);
});

startConsumer().catch((e) => {
    console.error("Failed to start RabbitMQ consumer:", e);
    process.exit(1);
});

startGrpcServer();

// Reset queue every day at midnight SGT (UTC+8 = 16:00 UTC)
cron.schedule("0 16 * * *", async () => {
    console.log("[Cron] Running daily queue reset");
    try {
        await resetDailyQueue();
        console.log("[Cron] Daily queue reset complete");
    } catch (e) {
        console.error("[Cron] Daily queue reset failed:", e);
    }
}, { timezone: "UTC" });