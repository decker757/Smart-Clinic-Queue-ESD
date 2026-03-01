import express from "express";
import queueRouter from "./controller/Queue";
import { startConsumer } from "./consumer/rabbitmq";

const app = express();
app.use(express.json());
app.use("/api/queue", queueRouter);

const PORT = parseInt(process.env.PORT || "3002");

app.listen(PORT, () => {
    console.log(`Queue coordinator service running on port ${PORT}`);
});

startConsumer().catch((e) => {
    console.error("Failed to start RabbitMQ consumer:", e);
    process.exit(1);
});
