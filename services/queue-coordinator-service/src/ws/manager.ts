import { WebSocketServer, WebSocket } from "ws";
import { IncomingMessage, Server } from "http";
import pool from "../db/db";
import { decodeJwtPayload } from "../utils/jwt";
import { listActiveQueue } from "../service/Queue";

// Map of appointment_id → set of connected WebSocket clients (patients)
const subscriptions = new Map<string, Set<WebSocket>>();

// Set of connected staff clients — receive all queue updates
const staffClients = new Set<WebSocket>();

const STAFF_ROLES = new Set(["staff", "doctor", "admin"]);

// Both WSS instances use noServer:true so we can route upgrade events manually.
// This avoids the ws library's path-matching bug where the first WSS closes the
// socket with 400 if the path doesn't match, preventing the second WSS from handling it.
const patientWss = new WebSocketServer({ noServer: true });
const staffWss   = new WebSocketServer({ noServer: true });

patientWss.on("connection", async (ws: WebSocket, req: IncomingMessage) => {
    try {
        const url = new URL(req.url ?? "", `http://${req.headers.host}`);
        const appointmentId = url.searchParams.get("appointment_id");
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

staffWss.on("connection", async (ws: WebSocket, req: IncomingMessage) => {
    try {
        const url = new URL(req.url ?? "", `http://${req.headers.host}`);
        const token = url.searchParams.get("token");

        if (!token) {
            ws.close(1008, "token query param required");
            return;
        }

        const payload = decodeJwtPayload(token);
        if (!payload?.sub || !STAFF_ROLES.has(payload.role as string)) {
            ws.close(1008, "Staff access required");
            return;
        }

        staffClients.add(ws);

        try {
            const entries = await listActiveQueue();
            ws.send(JSON.stringify({ type: "snapshot", entries }));
        } catch (e) {
            console.error("[WS:staff] Failed to send snapshot:", e);
        }
        console.log(`[WS:staff] Client connected (${staffClients.size} total)`);

        ws.on("close", () => {
            staffClients.delete(ws);
        });

        ws.on("error", (err) => {
            console.error("[WS:staff] Error:", err.message);
        });
    } catch (e) {
        console.error("[WS:staff] Unexpected error:", e);
        ws.close(1011, "Internal error");
    }
});

export function createWsServer(server: Server): void {
    server.on("upgrade", (req, socket, head) => {
        const pathname = new URL(req.url ?? "", `http://${req.headers.host}`).pathname;

        if (pathname === "/api/queue/ws/staff") {
            staffWss.handleUpgrade(req, socket, head, (ws) => {
                staffWss.emit("connection", ws, req);
            });
        } else if (pathname === "/api/queue/ws") {
            patientWss.handleUpgrade(req, socket, head, (ws) => {
                patientWss.emit("connection", ws, req);
            });
        } else {
            socket.destroy();
        }
    });

    console.log("[WS] WebSocket servers initialized (/api/queue/ws, /api/queue/ws/staff)");
}

/**
 * Push a queue update to all clients watching a specific appointment,
 * and to all connected staff clients.
 */
export function broadcastQueueUpdate(appointmentId: string, data: object): void {
    const clients = subscriptions.get(appointmentId);
    if (clients && clients.size > 0) {
        const payload = JSON.stringify(data);
        for (const ws of clients) {
            if (ws.readyState === WebSocket.OPEN) ws.send(payload);
        }
    }

    if (staffClients.size > 0) {
        const staffPayload = JSON.stringify({ type: "update", entry: data });
        for (const ws of staffClients) {
            if (ws.readyState === WebSocket.OPEN) ws.send(staffPayload);
        }
    }
}
