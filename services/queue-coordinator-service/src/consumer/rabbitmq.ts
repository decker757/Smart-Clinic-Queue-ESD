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
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "consultation.completed");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "queue.checked_in");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "queue.removed");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "queue.deprioritized");

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

            } else if (routingKey === "queue.checked_in") {
                try {
                    const entry = await QueueService.checkIn(content.appointment_id);
                    broadcastQueueUpdate(entry.appointment_id, entry);
                    console.log(`[Queue] Checked in appointment ${content.appointment_id}`);
                } catch (e: any) {
                    // Already checked in or in a terminal state — safe to ignore
                    console.warn(`[Queue] check-in skipped for ${content.appointment_id}: ${e.message}`);
                }

            } else if (routingKey === "queue.removed") {
                try {
                    const entry = await QueueService.removeFromQueue(content.appointment_id);
                    broadcastQueueUpdate(entry.appointment_id, entry);
                    console.log(`[Queue] Removed appointment ${content.appointment_id} from queue`);
                } catch (e: any) {
                    // Already removed (e.g. TTL fired after patient already said "No") — safe to ignore
                    console.warn(`[Queue] removal skipped for ${content.appointment_id}: ${e.message}`);
                }

            } else if (routingKey === "queue.deprioritized") {
                try {
                    const entry = await QueueService.deprioritize(content.appointment_id);
                    broadcastQueueUpdate(entry.appointment_id, entry);
                    console.log(`[Queue] Deprioritized appointment ${content.appointment_id}`);
                } catch (e: any) {
                    console.warn(`[Queue] deprioritize skipped for ${content.appointment_id}: ${e.message}`);
                }

            } else if (routingKey === "consultation.completed") {
                try {
                    const entry = await QueueService.completeAppointment(content.appointment_id);
                    broadcastQueueUpdate(entry.appointment_id, entry);
                    console.log(`[Queue] Marked appointment ${content.appointment_id} as done`);
                } catch (e: any) {
                    if (e.message === "Appointment not found or cannot be completed") {
                        console.warn(`[Queue] Appointment ${content.appointment_id} not in queue or already done`);
                    } else {
                        throw e;
                    }
                }

            } else if (routingKey === "appointment.cancelled") {
                try {
                    await QueueService.removeFromQueue(content.appointment_id);
                    console.log(`[Queue] Removed appointment ${content.appointment_id} from queue`);
                } catch (e: any) {
                    if (e.message === "Appointment not in queue") {
                        console.warn(`[Queue] Appointment ${content.appointment_id} was not in queue, skipping removal`);
                    } else {
                        throw e;
                    }
                }
            }

            channel.ack(msg);
        } catch (e) {
            console.error(`[RabbitMQ] Error processing ${routingKey}:`, e);
            channel.nack(msg, false, false);
        }
    });

    console.log("[RabbitMQ] Queue coordinator listening on", QUEUE_NAME);
}
