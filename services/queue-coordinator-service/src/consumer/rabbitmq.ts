import amqp from "amqplib";
import { AppointmentInfo } from "../model/Queue";
import * as QueueService from "../service/Queue";
import { broadcastQueueUpdate } from "../ws/manager";

const EXCHANGE = "clinic.events";
const QUEUE_NAME = "queue-coordinator.appointment-events";

export async function startConsumer(): Promise<void> {
    const url = process.env.RABBITMQ_URL;
    if (!url) throw new Error("RABBITMQ_URL is not set");

    const connection = await amqp.connect(url);
    const channel = await connection.createChannel();

    await channel.assertExchange(EXCHANGE, "topic", { durable: true });
    await channel.assertQueue(QUEUE_NAME, { durable: true });
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "appointment.booked");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "appointment.cancelled");

    channel.consume(QUEUE_NAME, async (msg) => {
        if (!msg) return;

        const routingKey = msg.fields.routingKey;
        let content: any;
        try {
            content = JSON.parse(msg.content.toString());
        } catch {
            console.error("[RabbitMQ] Failed to parse message, discarding");
            channel.nack(msg, false, false);
            return;
        }

        try {
            if (routingKey === "appointment.booked") {
                const appointment: AppointmentInfo = {
                    appointment_id: content.appointment_id,
                    patient_id: content.patient_id,
                    doctor_id: content.doctor_id ?? undefined,
                    start_time: content.start_time ? new Date(content.start_time) : undefined,
                    session: content.session ?? undefined,
                };
                const entry = await QueueService.addToQueue(appointment);
                broadcastQueueUpdate(entry.appointment_id, entry);
                console.log(`[Queue] Added appointment ${content.appointment_id} to queue`);
            } else if (routingKey === "appointment.cancelled") {
                try {
                    await QueueService.removeFromQueue(content.appointment_id);
                    console.log(`[Queue] Removed appointment ${content.appointment_id} from queue`);
                } catch (e: any) {
                    if (e.message === "Appointment not in queue") {
                        // appointment was never queued (e.g. cancelled before check-in) — safe to ignore
                        console.warn(`[Queue] Appointment ${content.appointment_id} was not in queue, skipping removal`);
                    } else {
                        throw e;
                    }
                }
            }
            channel.ack(msg);
        } catch (e) {
            console.error(`[RabbitMQ] Error processing ${routingKey}:`, e);
            // nack without requeue to avoid infinite loops on persistent DB errors
            channel.nack(msg, false, false);
        }
    });

    console.log("[RabbitMQ] Queue coordinator listening on", QUEUE_NAME);
}
