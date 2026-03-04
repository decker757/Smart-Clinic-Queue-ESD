import http from "http";
import express, { Request, Response, NextFunction } from "express";
import queueRouter from "./controller/Queue";
import { startConsumer } from "./consumer/rabbitmq";
import { createWsServer } from "./ws/manager";

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
