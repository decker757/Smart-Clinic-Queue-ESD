import { Router, Request, Response } from "express";
import { getPatient } from "../patientClient";

const router = Router();

// GET /api/doctors/patients/:patient_id — fetch patient info from Patient Service
router.get("/:patient_id", async (req: Request, res: Response) => {
    try {
        const patient = await getPatient(req.params.patient_id as string);
        res.json(patient);
    } catch (e: any) {
        if (e.code === 5) {
            res.status(404).json({ error: "Patient not found" });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

export default router;
