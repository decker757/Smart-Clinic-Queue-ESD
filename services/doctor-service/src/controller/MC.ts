import { Router, Request, Response } from "express";
import * as MCService from "../service/MC";

const router = Router();

// POST /api/doctors/mc — issue MC
router.post("/", async (req: Request, res: Response) => {
    const { appointment_id, doctor_id, patient_id, start_date, end_date, reason } = req.body;
    if (!doctor_id || !patient_id || !start_date || !end_date) {
        res.status(400).json({ error: "doctor_id, patient_id, start_date and end_date are required" });
        return;
    }
    try {
        const mc = await MCService.issueMC({ appointment_id, doctor_id, patient_id, start_date, end_date, reason });
        res.status(201).json(mc);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

// GET /api/doctors/mc/:patient_id — view MCs for a patient
router.get("/:patient_id", async (req: Request, res: Response) => {
    try {
        const mcs = await MCService.getMCsByPatient(req.params.patient_id as string);
        res.json(mcs);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
