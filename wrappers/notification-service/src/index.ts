import express from "express";
import { startConsumer } from "./consumer/rabbitmq";

const app = express();

app.get("/health", (_req, res) => res.json({ status: "ok", service: "notification-service" }));

const PORT = process.env.PORT ?? 3004;
app.listen(PORT, () => console.log(`[Notification] Service running on :${PORT}`));

startConsumer().catch((e) => {
    console.error("Failed to start RabbitMQ consumer:", e);
    process.exit(1);
});
