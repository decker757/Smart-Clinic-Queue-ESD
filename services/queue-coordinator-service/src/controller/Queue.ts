import { Router, Request, Response } from "express";
import * as QueueService from "../service/Queue";

const router = Router();

// GET /queue/position/:appointment_id — patient checks their queue position
router.get("/position/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const position = await QueueService.getQueuePosition(appointment_id);
        res.json(position);
    } catch (e: any) {
        if (e.message === "Appointment not in queue") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// POST /queue/checkin/:appointment_id — patient confirms arrival
router.post("/checkin/:appointment_id", async (req: Request, res: Response) => {
    try {
        const appointment_id = req.params.appointment_id as string;
        const entry = await QueueService.checkIn(appointment_id);
        res.json(entry);
    } catch (e: any) {
        if (e.message === "Appointment not in queue") {
            res.status(404).json({ error: e.message });
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
        res.json(entry);
    } catch (e: any) {
        if (e.message === "Appointment not found or already resolved") {
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
        if (!session) {
            res.status(400).json({ error: "session is required (morning or afternoon)" });
            return;
        }
        const next = await QueueService.callNext(session, doctor_id);
        res.json(next);
    } catch (e: any) {
        if (e.message === "No waiting patients in queue") {
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
