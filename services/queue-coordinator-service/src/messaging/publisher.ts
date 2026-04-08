import amqp from "amqplib";

const EXCHANGE = "clinic.events";
const APPROACHING_TTL_QUEUE = "approaching-checkin-ttl";
const APPROACHING_TTL_MS = 10 * 60 * 1000; // 10 minutes

let channel: amqp.Channel | null = null;

export async function initPublisher(): Promise<void> {
    const url = process.env.RABBITMQ_URL;
    if (!url) throw new Error("RABBITMQ_URL is not set");

    const connection = await amqp.connect(url);
    channel = await connection.createChannel();

    // Null out the channel on close or error so publish functions return false
    // rather than silently dropping messages after a broker restart.
    channel.on("close", () => {
        console.warn("[Publisher] Channel closed — publisher unavailable until restart");
        channel = null;
    });
    channel.on("error", (err: Error) => {
        console.error("[Publisher] Channel error:", err.message, "— publisher unavailable until restart");
        channel = null;
    });
    connection.on("close", () => {
        console.warn("[Publisher] Connection closed — publisher unavailable until restart");
        channel = null;
    });
    connection.on("error", (err: Error) => {
        console.error("[Publisher] Connection error:", err.message, "— publisher unavailable until restart");
        channel = null;
    });

    await channel.assertExchange(EXCHANGE, "topic", { durable: true });
    await channel.assertQueue(APPROACHING_TTL_QUEUE, {
        durable: true,
        arguments: {
            "x-message-ttl": APPROACHING_TTL_MS,
            "x-dead-letter-exchange": EXCHANGE,
            "x-dead-letter-routing-key": "queue.checkin_timeout",
        },
    });

    console.log("[Publisher] RabbitMQ publisher initialized");
}

export function publishApproaching(payload: object): boolean {
    if (!channel) return false;
    channel.publish(
        EXCHANGE,
        "queue.approaching",
        Buffer.from(JSON.stringify(payload)),
        { contentType: "application/json", persistent: true },
    );
    return true;
}

export function publishApproachingWithTtl(payload: object): boolean {
    if (!channel) return false;
    channel.sendToQueue(
        APPROACHING_TTL_QUEUE,
        Buffer.from(JSON.stringify(payload)),
        { contentType: "application/json", persistent: true },
    );
    return true;
}

export function publishEvent(routingKey: string, payload: object): void {
    if (!channel) return;
    channel.publish(
        EXCHANGE,
        routingKey,
        Buffer.from(JSON.stringify(payload)),
        { contentType: "application/json", persistent: true },
    );
}
