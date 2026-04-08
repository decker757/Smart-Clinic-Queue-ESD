import { Router, Request, Response } from "express";
import * as QueueService from "../service/Queue";
import { broadcastQueueUpdate, broadcastAllPatientPositions } from "../ws/manager";
import { callerIdFromAuthHeader } from "../utils/jwt";
import { publishEvent } from "../messaging/publisher";

const router = Router();

// GET /queue/active — staff lists all active queue entries
router.get("/active", async (_req: Request, res: Response) => {
    try {
        const entries = await QueueService.listActiveQueue();
        res.json(entries);
    } catch {
        res.status(500).json({ error: "Internal server error" });
    }
});

// GET /queue/position/:appointment_id — patient checks their queue position
router.get("/position/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const callerId = callerIdFromAuthHeader(req.headers.authorization) ?? undefined;
        const position = await QueueService.getQueuePosition(appointment_id, callerId);
        res.json(position);
    } catch (e: any) {
        if (e.message === "Appointment not in queue") {
            res.status(404).json({ error: e.message });
        } else if (e.message === "Forbidden") {
            res.status(403).json({ error: "Forbidden" });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// POST /queue/checkin/:appointment_id — patient confirms arrival
router.post("/checkin/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const callerId = callerIdFromAuthHeader(req.headers.authorization) ?? undefined;
        const entry = await QueueService.checkIn(appointment_id, callerId);
        broadcastQueueUpdate(appointment_id, entry);
        res.json(entry);
        broadcastAllPatientPositions().catch(() => {});
    } catch (e: any) {
        if (e.message === "Appointment not in queue") {
            res.status(404).json({ error: e.message });
        } else if (e.message === "Forbidden") {
            res.status(403).json({ error: "Forbidden" });
        } else if (e.message.startsWith("Cannot check in")) {
            res.status(409).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// POST /queue/no-show/:appointment_id — patient did not show up (called by notification service on timeout)
router.post("/no-show/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const entry = await QueueService.markNoShow(appointment_id);
        broadcastQueueUpdate(appointment_id, entry);
        res.json(entry);
        broadcastAllPatientPositions().catch(() => {});
    } catch (e: any) {
        if (e.message === "Appointment not found or already resolved") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// POST /queue/complete/:appointment_id — doctor finishes consultation with a patient
router.post("/complete/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const entry = await QueueService.completeAppointment(appointment_id);
        broadcastQueueUpdate(appointment_id, entry);
        res.json(entry);
        broadcastAllPatientPositions().catch(() => {});
    } catch (e: any) {
        if (e.message === "Appointment not found or cannot be completed") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// POST /queue/call-next — doctor calls the next patient
router.post("/call-next", async (req: Request, res: Response) => {
    try {
        const { session, doctor_id } = req.body;
        if (!session && !doctor_id) {
            res.status(400).json({ error: "provide session (morning or afternoon) or doctor_id" });
            return;
        }
        const next = await QueueService.callNext(session, doctor_id);
        broadcastQueueUpdate(next.appointment_id, next);
        publishEvent("queue.called", {
            appointment_id: next.appointment_id,
            patient_id: next.patient_id,
            doctor_id: next.doctor_id,
            queue_number: next.queue_number,
        });
        res.json(next);
        broadcastAllPatientPositions().catch(() => {});
    } catch (e: any) {
        if (e.message === "No checked-in patients in queue") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// GET /queue/current/:doctor_id — get the currently called patient for a doctor
router.get("/current/:doctor_id", async (req: Request, res: Response) => {
    try {
        const entry = await QueueService.getCurrentCalled(req.params.doctor_id as string);
        if (!entry) return res.status(404).json({ error: "No current patient" });
        res.json(entry);
    } catch {
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /queue/deprioritize/:appointment_id — shift late patient back by slot bands
// Body: { travel_eta_minutes: number }  (optional, defaults to 0 → minimum 1 slot shift)
router.post("/deprioritize/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const travel_eta_minutes = Number(req.body?.travel_eta_minutes ?? 0);
        const entry = await QueueService.deprioritize(appointment_id, travel_eta_minutes);
        broadcastQueueUpdate(appointment_id, entry);
        publishEvent("queue.deprioritized", {
            appointment_id: entry.appointment_id,
            patient_id: entry.patient_id,
            travel_eta_minutes,
        });
        res.json(entry);
        broadcastAllPatientPositions().catch(() => {});
    } catch (e: any) {
        if (e.message === "Appointment not in queue") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// POST /queue/reset — reset queue at start of day
router.post("/reset", async (_req: Request, res: Response) => {
    try {
        await QueueService.resetDailyQueue();
        res.json({ message: "Queue reset successfully" });
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
