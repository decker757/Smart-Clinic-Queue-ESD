import { Router, Request, Response } from "express";
import * as PatientService from "../service/Patient";
import { requireAuth } from "../middleware/auth";

const router = Router();

// GET /api/patients/:id
router.get("/:id", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    try {
        const patient = await PatientService.getPatient(req.params.id);
        if (!patient) return res.status(404).json({ error: "Patient not found" });
        res.json(patient);
    } catch (e) {
        console.error("[Patient] getPatient error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /api/patients — create profile on first login
router.post("/", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    const { phone, dob, nric, allergies } = req.body;

    try {
        const patient = await PatientService.createPatient(callerId, { phone, dob, nric, allergies });
        res.status(201).json(patient);
    } catch (e) {
        console.error("[Patient] createPatient error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// PUT /api/patients/:id — update profile
router.put("/:id", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    const { phone, dob, nric, allergies } = req.body;

    try {
        const patient = await PatientService.updatePatient(req.params.id, { phone, dob, nric, allergies });
        if (!patient) return res.status(404).json({ error: "Patient not found" });
        res.json(patient);
    } catch (e) {
        console.error("[Patient] updatePatient error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
