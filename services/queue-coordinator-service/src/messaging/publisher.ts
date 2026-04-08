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

export function publishApproaching(payload: object): void {
    if (!channel) return;
    channel.publish(
        EXCHANGE,
        "queue.approaching",
        Buffer.from(JSON.stringify(payload)),
        { contentType: "application/json", persistent: true },
    );
}

export function publishApproachingWithTtl(payload: object): void {
    if (!channel) return;
    channel.sendToQueue(
        APPROACHING_TTL_QUEUE,
        Buffer.from(JSON.stringify(payload)),
        { contentType: "application/json", persistent: true },
    );
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
