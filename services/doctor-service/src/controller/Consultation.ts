import { Router, Request, Response } from "express";
import * as ConsultationService from "../service/Consultation";

const router = Router();

// POST /api/doctors/consultations — doctor writes notes after appointment
router.post("/", async (req: Request, res: Response) => {
    const { appointment_id, doctor_id, patient_id, notes, diagnosis } = req.body;
    if (!doctor_id || !patient_id) {
        res.status(400).json({ error: "doctor_id and patient_id are required" });
        return;
    }
    try {
        const consultation = await ConsultationService.createConsultation({
            appointment_id, doctor_id, patient_id, notes, diagnosis
        });
        res.status(201).json(consultation);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

// GET /api/doctors/consultations/:patient_id — view consultation history
router.get("/:patient_id", async (req: Request, res: Response) => {
    try {
        const consultations = await ConsultationService.getConsultationsByPatient(req.params.patient_id as string);
        res.json(consultations);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
