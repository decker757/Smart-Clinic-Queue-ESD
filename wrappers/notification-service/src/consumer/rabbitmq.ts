import amqp from "amqplib";
import * as AppointmentHandlers from "../handlers/appointment";
import * as QueueHandlers from "../handlers/queue";
import * as DoctorHandlers from "../handlers/doctor";
import * as ConsultationHandlers from "../handlers/consultation";
import * as PaymentHandlers from "../handlers/payment";

const EXCHANGE = "clinic.events";
const QUEUE_NAME = "notification-service.events";

const HANDLERS: Record<string, (payload: any) => Promise<void>> = {
    "appointment.booked":    AppointmentHandlers.handleAppointmentBooked,
    "appointment.cancelled": AppointmentHandlers.handleAppointmentCancelled,
    "appointment.created":   AppointmentHandlers.handleAppointmentCreated,
    "queue.approaching":     QueueHandlers.handleApproaching,
    "queue.checked_in":      QueueHandlers.handleCheckedIn,
    "queue.late_detected":   QueueHandlers.handleLateDetected,
    "queue.deprioritized":   QueueHandlers.handleDeprioritized,
    "queue.removed":         QueueHandlers.handleRemoved,
    "queue.called":          QueueHandlers.handleQueueCalled,
    "queue.eta_alert":       QueueHandlers.handleEtaAlert,
    "doctor.unavailable":        DoctorHandlers.handleDoctorUnavailable,
    "consultation.completed":    ConsultationHandlers.handleConsultationCompleted,
    "payment.completed":         PaymentHandlers.handlePaymentCompleted,
};

export async function startConsumer(): Promise<void> {
    const url = process.env.RABBITMQ_URL;
    if (!url) throw new Error("RABBITMQ_URL is not set");

    const connection = await amqp.connect(url);
    const channel = await connection.createChannel();

    await channel.assertExchange(EXCHANGE, "topic", { durable: true});
    await channel.assertQueue(QUEUE_NAME, { durable: true });
    
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "appointment.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "queue.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "doctor.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "consultation.*");
    await channel.bindQueue(QUEUE_NAME, EXCHANGE, "payment.*");

    console.log(`[RabbitMQ] Notification service listening on ${QUEUE_NAME}`);

    channel.consume(QUEUE_NAME, async (msg) =>{
        if (!msg) return;

        const routingKey = msg.fields.routingKey;
        let content: any;

        try{
            content = JSON.parse(msg.content.toString());
        } catch {
            console.error(`[RabbitMQ] Failed to parse message, discarding`);
            channel.nack(msg, false, false);
            return;
        }

        const handler = HANDLERS[routingKey];
        if (!handler){
            console.warn(`[RabbitMQ] No handler for ${routingKey}, skipping`);
            channel.ack(msg);
            return;
        }

        try{
            await handler(content);
            channel.ack(msg);
        } catch(e){
            console.error(`[RabbitMQ] Error handling ${routingKey}:`, e);
            channel.nack(msg, false, false);
        }
    });

}
