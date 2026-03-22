import { Router, Request, Response } from "express";
import * as DoctorService from "../service/Doctor";

const router = Router();

// GET /api/doctors — list all doctors (used by frontend to pick a doctor)
router.get("/", async (_req: Request, res: Response) => {
    try {
        const doctors = await DoctorService.listDoctors();
        res.json(doctors);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

// GET /api/doctors/:id — get one doctor (called by Doctor Queue Orchestrator)
router.get("/:id", async (req: Request, res: Response) => {
    try {
        const doctor = await DoctorService.getDoctorById(req.params.id as string);
        res.json(doctor);
    } catch (e: any) {
        if (e.message === "Doctor not found") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

// GET /api/doctors/:id/slots?date=YYYY-MM-DD — get available slots filtered by date
router.get("/:id/slots", async (req: Request, res: Response) => {
    try {
        const date = req.query.date as string | undefined;
        const slots = await DoctorService.getDoctorSlots(req.params.id as string, date);
        res.json(slots);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /api/doctors/:id/slots/generate — generate 15-min slots over a date range
router.post("/:id/slots/generate", async (req: Request, res: Response) => {
    try {
        const { start_date, end_date } = req.body;
        if (!start_date || !end_date) {
            res.status(400).json({ error: "start_date and end_date are required (YYYY-MM-DD)" });
            return;
        }
        const result = await DoctorService.generateSlots(req.params.id as string, start_date, end_date);
        res.status(201).json(result);
    } catch (e) {
        res.status(500).json({ error: "Internal server error" });
    }
});

// PATCH /api/doctors/slots/:slot_id — mark slot booked/available (called by Appointment Service)
router.patch("/slots/:slot_id", async (req: Request, res: Response) => {
    try {
        const { status } = req.body;
        const VALID_STATUSES = ["available", "booked", "blocked"];
        if (!status || !VALID_STATUSES.includes(status)) {
            res.status(400).json({ error: `status must be one of: ${VALID_STATUSES.join(", ")}` });
            return;
        }
        const slot = await DoctorService.updateSlotStatus(req.params.slot_id as string, status);
        res.json(slot);
    } catch (e: any) {
        if (e.message === "Slot not found") {
            res.status(404).json({ error: e.message });
        } else {
            res.status(500).json({ error: "Internal server error" });
        }
    }
});

export default router;