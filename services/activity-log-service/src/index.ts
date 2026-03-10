import express, { Request, Response, NextFunction } from "express";
import activityLogRouter from "./controller/ActivityLog";
import { startConsumer } from "./consumer/rabbitmq";

const app = express();

// CORS — allow all origins (same pattern as queue-coordinator)
app.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
        res.status(204).end();
        return;
    }
    next();
});

app.use(express.json());

// Health check
app.get("/health", (_req: Request, res: Response) => {
    res.json({ status: "ok", service: "activity-log-service" });
});

// Mount routes
app.use("/api/activity-log", activityLogRouter);

const PORT = parseInt(process.env.PORT || "3005");

app.listen(PORT, () => {
    console.log(`Activity log service running on port ${PORT}`);
});

// Start RabbitMQ consumer
startConsumer().catch((e) => {
    console.error("Failed to start RabbitMQ consumer:", e);
    process.exit(1);
});
