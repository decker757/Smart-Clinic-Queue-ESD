import "dotenv/config";
import express, { Request, Response, NextFunction } from "express";
import swaggerUi from "swagger-ui-express";
import activityLogRouter from "./controller/ActivityLog";
import { startConsumer } from "./consumer/rabbitmq";
import { swaggerSpec } from "./swagger";

const app = express();

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

app.get("/health", (_req: Request, res: Response) => {
    res.json({ status: "ok", service: "activity-log-service" });
});

app.get("/api/activity-log/openapi.json", (_req: Request, res: Response) => res.json(swaggerSpec));
app.use("/api/activity-log/docs", swaggerUi.serve, swaggerUi.setup(swaggerSpec));

app.use("/api/activity-log", activityLogRouter);

const PORT = parseInt(process.env.PORT || "3005");

app.listen(PORT, () => {
    console.log(`Activity log service running on port ${PORT}`);
});

startConsumer().catch((e) => {
    console.error("Failed to start RabbitMQ consumer:", e);
    process.exit(1);
});
