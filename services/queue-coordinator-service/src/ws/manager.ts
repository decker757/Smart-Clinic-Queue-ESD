import { WebSocketServer, WebSocket } from "ws";
import { IncomingMessage, Server } from "http";
import pool from "../db/db";
import { decodeJwtPayload } from "../utils/jwt";

// Map of appointment_id → set of connected WebSocket clients
const subscriptions = new Map<string, Set<WebSocket>>();

export function createWsServer(server: Server): WebSocketServer {
    const wss = new WebSocketServer({ server, path: "/api/queue/ws" });

    wss.on("connection", async (ws: WebSocket, req: IncomingMessage) => {
        // Outer guard: the ws library does not handle rejected async callbacks,
        // so an unexpected throw would silently become an unhandled rejection.
        try {
            const url = new URL(req.url ?? "", `http://${req.headers.host}`);
            const appointmentId = url.searchParams.get("appointment_id");

            // JWT is passed as ?token= because browsers cannot set custom headers
            // during the HTTP→WS upgrade handshake. Kong validates the signature;
            // we decode here only to extract the caller's patient_id.
            const token = url.searchParams.get("token");

            if (!appointmentId || !token) {
                ws.close(1008, "appointment_id and token query params required");
                return;
            }

            const payload = decodeJwtPayload(token);
            const callerId = payload?.sub as string | undefined;

            if (!callerId) {
                ws.close(1008, "Invalid token payload");
                return;
            }

            // Verify the caller owns this appointment (if it is already in the queue).
            // If the entry does not exist yet, we allow the subscription — it will be
            // idle until the booking event is processed by the RabbitMQ consumer.
            try {
                const { rows } = await pool.query(
                    `SELECT patient_id FROM queue.queue_entries WHERE appointment_id = $1`,
                    [appointmentId],
                );
                if (rows.length > 0 && rows[0].patient_id !== callerId) {
                    ws.close(1008, "Forbidden");
                    return;
                }
            } catch (e) {
                console.error("[WS] Ownership check failed:", e);
                ws.close(1011, "Internal error");
                return;
            }

            // Register subscription
            if (!subscriptions.has(appointmentId)) {
                subscriptions.set(appointmentId, new Set());
            }
            subscriptions.get(appointmentId)!.add(ws);
            console.log(`[WS] Client subscribed to appointment ${appointmentId}`);

            ws.on("close", () => {
                subscriptions.get(appointmentId)?.delete(ws);
                if (subscriptions.get(appointmentId)?.size === 0) {
                    subscriptions.delete(appointmentId);
                }
            });

            ws.on("error", (err) => {
                console.error(`[WS] Error for appointment ${appointmentId}:`, err.message);
            });
        } catch (e) {
            console.error("[WS] Unexpected error in connection handler:", e);
            ws.close(1011, "Internal error");
        }
    });

    return wss;
}

/**
 * Push a queue update to all clients watching a specific appointment.
 * Payload shape mirrors GET /api/queue/position/:id response.
 */
export function broadcastQueueUpdate(appointmentId: string, data: object): void {
    const clients = subscriptions.get(appointmentId);
    if (!clients || clients.size === 0) return;

    const payload = JSON.stringify(data);
    for (const ws of clients) {
        if (ws.readyState === WebSocket.OPEN) {
            ws.send(payload);
        }
    }
}
