/**
 * RabbitMQ consumer for the Activity Log service.
 *
 * Subscribes to ALL clinic events via wildcard binding on the
 * "clinic.events" topic exchange. Every event is recorded into
 * the activity_log.logs table for auditing and patient history.
 *
 * Routing keys consumed:
 *   - appointment.booked      (from composite-appointment)
 *   - appointment.cancelled   (from composite-appointment)
 *   - checkin.completed       (from check-in orchestrator — future)
 *   - queue.called            (from queue coordinator — future)
 *   - queue.completed         (from queue coordinator — future)
 *   - queue.no_show           (from queue coordinator — future)
 *
 * The wildcard bindings (#) ensure this service automatically picks up
 * any NEW event types added later without code changes.
 */

import amqp from "amqplib";
import * as ActivityLogService from "../service/ActivityLog";
import { ClinicEvent } from "../model/ActivityLog";

const EXCHANGE = "clinic.events";
const QUEUE_NAME = "activity-log.all-events";

export async function startConsumer(): Promise<void> {
    const url = process.env.RABBITMQ_URL;
    if (!url) throw new Error("RABBITMQ_URL is not set");

    const connection = await amqp.connect(url);
    const channel = await connection.createChannel();

    await channel.assertExchange(EXCHANGE, "topic", { durable: true });
    await channel.assertQueue(QUEUE_NAME, { durable: true });

    // Bind to all event types using wildcards
    // "#" matches zero or more words — catches everything on this exchange
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "appointment.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "checkin.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "queue.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "patient.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "payment.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "consultation.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "staff.*");

    console.log(`[RabbitMQ] Activity log listening on ${QUEUE_NAME}`);

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
            // Build a ClinicEvent from the raw message
            // - payment.* uses consultation_id instead of appointment_id
            // - staff.* events often only carry appointment_id (no patient_id)
            // - Stripe metadata may not propagate patient_id
            const event: ClinicEvent = {
                event_type: routingKey,
                patient_id: content.patient_id ?? content.consultation_id ?? content.appointment_id ?? "unknown",
                appointment_id: content.appointment_id ?? content.consultation_id ?? undefined,
                actor: content.actor ?? content.checked_in_by ?? content.viewed_by ?? "system",
                payload: content,
            };

            await ActivityLogService.recordEvent(event);
            console.log(`[ActivityLog] Recorded ${routingKey} for patient ${event.patient_id}`);

            channel.ack(msg);
        } catch (e) {
            console.error(`[RabbitMQ] Error processing ${routingKey}:`, e);
            // nack without requeue to avoid infinite loops
            channel.nack(msg, false, false);
        }
    });
}
