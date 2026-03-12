/**
 * REST controller for the Activity Log service.
 *
 * Endpoints:
 *   GET /api/activity-log/patients/:id/history       — all events for a patient
 *   GET /api/activity-log/appointments/:id/history   — all events for an appointment
 */

import { Router, Request, Response } from "express";
import * as ActivityLogService from "../service/ActivityLog";
import { requireAuth } from "../middleware/auth";

const router = Router();

// GET /api/activity-log/patients/:id/history — patient activity timeline
router.get("/patients/:id/history", requireAuth, async (req: Request, res: Response) => {
    try {
        const callerId = (req as any).callerId as string;
        if (callerId !== req.params.id) {
            return res.status(403).json({ error: "Forbidden" });
        }

        const patient_id = req.params.id;
        const limit = parseInt(String(req.query.limit)) || 50;
        const offset = parseInt(String(req.query.offset)) || 0;

        const logs = await ActivityLogService.getPatientHistory(patient_id, limit, offset);
        res.json(logs);
    } catch (e) {
        console.error("Error fetching patient history:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// GET /api/activity-log/appointments/:id/history — full lifecycle of one appointment
// Ownership enforced: only returns entries where patient_id matches the caller's JWT sub
router.get("/appointments/:id/history", requireAuth, async (req: Request, res: Response) => {
    try {
        const callerId = String((req as any).callerId);
        const appointment_id = String(req.params.id);

        const logs = await ActivityLogService.getAppointmentHistory(appointment_id, callerId);
        res.json(logs);
    } catch (e) {
        console.error("Error fetching appointment history:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
