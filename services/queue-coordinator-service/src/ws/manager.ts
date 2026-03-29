import { WebSocketServer, WebSocket } from "ws";
import { IncomingMessage, Server } from "http";
import pool from "../db/db";
import { decodeJwtPayload } from "../utils/jwt";
import { markApproachingNotified } from "../service/Queue";
import { publishApproaching, publishApproachingWithTtl } from "../messaging/publisher";

const NOTIFY_THRESHOLD = 3; // notify when this many patients are ahead

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

// Ping all connected clients every 30s to keep ALB idle connections alive (ALB default timeout = 60s)
setInterval(() => {
    for (const clients of subscriptions.values()) {
        for (const ws of clients) {
            if (ws.readyState === WebSocket.OPEN) ws.ping();
        }
    }
    for (const ws of staffClients) {
        if (ws.readyState === WebSocket.OPEN) ws.ping();
    }
}, 30_000);

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

        // Send current status immediately so reconnects get fresh state without waiting for next event
        try {
            const { rows } = await pool.query(`
                SELECT e.*,
                    (SELECT COUNT(*) FROM queue.queue_entries a
                     WHERE a.queue_number < e.queue_number
                       AND a.status NOT IN ('done', 'cancelled')
                       AND (
                         (e.doctor_id IS NOT NULL AND a.doctor_id = e.doctor_id)
                         OR
                         (e.doctor_id IS NULL AND a.session = e.session AND a.doctor_id IS NULL)
                       )
                    ) AS active_ahead
                FROM queue.queue_entries e
                WHERE e.appointment_id = $1
                  AND e.status NOT IN ('done', 'cancelled')
            `, [appointmentId]);
            if (rows[0]) {
                const row = rows[0];
                if (!row.estimated_time) {
                    const aheadMinutes = Number(row.active_ahead) * 15;
                    row.estimated_time = new Date(Date.now() + aheadMinutes * 60 * 1000).toISOString();
                }
                ws.send(JSON.stringify(row));
            }
        } catch (e) {
            console.warn(`[WS] Failed to send initial status for ${appointmentId}:`, e);
        }

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
        if (!payload?.sub || !STAFF_ROLES.has((payload["custom:role"] ?? payload.role) as string)) {
            ws.close(1008, "Staff access required");
            return;
        }

        staffClients.add(ws);

        try {
            const entries = await getActiveQueueWithEta();
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

/**
 * Fetch all active queue entries with computed estimated_time.
 * Used for both the initial staff snapshot and post-mutation broadcasts.
 */
async function getActiveQueueWithEta() {
    const { rows } = await pool.query(`
        SELECT e.*,
            (SELECT COUNT(*) FROM queue.queue_entries a
             WHERE a.queue_number < e.queue_number
               AND a.status NOT IN ('done', 'cancelled')
               AND (
                 (e.doctor_id IS NOT NULL AND a.doctor_id = e.doctor_id)
                 OR
                 (e.doctor_id IS NULL AND a.session = e.session AND a.doctor_id IS NULL)
               )
            ) AS active_ahead,
            e.approaching_notified_at
        FROM queue.queue_entries e
        WHERE e.status NOT IN ('done', 'cancelled')
        ORDER BY e.queue_number ASC
    `);
    for (const row of rows) {
        if (!row.estimated_time) {
            const aheadMinutes = Number(row.active_ahead) * 15;
            row.estimated_time = new Date(Date.now() + aheadMinutes * 60 * 1000).toISOString();
        }
    }
    return rows;
}

/**
 * Re-compute and broadcast updated queue positions to all subscribed patients
 * and push a fresh snapshot to all staff clients.
 * Call this after any mutation that changes relative ordering.
 */
export async function broadcastAllPatientPositions(): Promise<void> {
    const rows = await getActiveQueueWithEta();

    // Push individual updates to subscribed patients
    for (const row of rows) {
        const clients = subscriptions.get(row.appointment_id);
        if (!clients || clients.size === 0) continue;
        const payload = JSON.stringify(row);
        for (const ws of clients) {
            if (ws.readyState === WebSocket.OPEN) ws.send(payload);
        }
    }

    // Push fresh snapshot to all staff clients so their list re-sorts
    if (staffClients.size > 0) {
        const staffPayload = JSON.stringify({ type: "snapshot", entries: rows });
        for (const ws of staffClients) {
            if (ws.readyState === WebSocket.OPEN) ws.send(staffPayload);
        }
    }

    // Notify waiting generic-queue patients who are within NOTIFY_THRESHOLD positions.
    // Fire-and-forget: failures here must not break the broadcast.
    for (const row of rows) {
        if (
            row.status === "waiting" &&
            row.session !== null &&          // generic queue only (no specific doctor slot)
            row.approaching_notified_at === null &&
            Number(row.active_ahead) <= NOTIFY_THRESHOLD
        ) {
            markApproachingNotified(row.appointment_id).then(() => {
                const payload = {
                    patient_id: row.patient_id,
                    appointment_id: row.appointment_id,
                };
                publishApproaching(payload);
                publishApproachingWithTtl(payload);
            }).catch((e) => console.error("[Approaching] Failed to notify:", e));
        }
    }
}
