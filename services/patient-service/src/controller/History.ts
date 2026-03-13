import { Router, Request, Response } from "express";
import * as HistoryService from "../service/History";
import { requireAuth } from "../middleware/auth";

const router = Router({ mergeParams: true });

// GET /api/patients/:id/history
router.get("/", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    try {
        const history = await HistoryService.getHistory(req.params.id);
        res.json(history);
    } catch (e) {
        console.error("[History] getHistory error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /api/patients/:id/history
router.post("/", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    const { diagnosis, diagnosed_at, notes } = req.body;
    if (!diagnosis) return res.status(400).json({ error: "diagnosis is required" });

    try {
        const entry = await HistoryService.addHistory(req.params.id, { diagnosis, diagnosed_at, notes });
        res.status(201).json(entry);
    } catch (e) {
        console.error("[History] addHistory error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
