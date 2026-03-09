/**
 * REST controller for the Activity Log service.
 *
 * Endpoints:
 *   GET /patients/:id/history              — all events for a patient
 *   GET /appointments/:id/history          — all events for an appointment
 */

import { Router, Request, Response } from "express";
import * as ActivityLogService from "../service/ActivityLog";

const router = Router();

// GET /patients/:id/history — patient activity timeline
router.get("/patients/:id/history", async (req: Request, res: Response) => {
    try {
        const patient_id = String(req.params.id);
        const limit = parseInt(String(req.query.limit)) || 50;
        const offset = parseInt(String(req.query.offset)) || 0;

        const logs = await ActivityLogService.getPatientHistory(patient_id, limit, offset);
        res.json(logs);
    } catch (e) {
        console.error("Error fetching patient history:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// GET /appointments/:id/history — full lifecycle of one appointment
router.get("/appointments/:id/history", async (req: Request, res: Response) => {
    try {
        const appointment_id = String(req.params.id);
        const logs = await ActivityLogService.getAppointmentHistory(appointment_id);
        res.json(logs);
    } catch (e) {
        console.error("Error fetching appointment history:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
