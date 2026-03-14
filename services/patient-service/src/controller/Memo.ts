import { Router, Request, Response } from "express";
import multer from "multer";
import * as MemoService from "../service/Memo";
import { requireAuth } from "../middleware/auth";

const router = Router({ mergeParams: true });

const ALLOWED_MIME_TYPES = new Set([
    "image/jpeg", "image/png",
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);

const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
    fileFilter: (_req, file, cb) => {
        if (ALLOWED_MIME_TYPES.has(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error(`File type not allowed: ${file.mimetype}`));
        }
    },
});

// GET /api/patients/:id/memos
router.get("/", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    try {
        const memos = await MemoService.getMemos(req.params.id);
        res.json(memos);
    } catch (e) {
        console.error("[Memo] getMemos error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /api/patients/:id/memos — text note
router.post("/", requireAuth, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    const { title, content } = req.body;
    if (!title || !content) return res.status(400).json({ error: "title and content are required" });

    try {
        const memo = await MemoService.createTextMemo(req.params.id, title, content);
        res.status(201).json(memo);
    } catch (e) {
        console.error("[Memo] createTextMemo error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /api/patients/:id/memos/upload — file upload
router.post("/upload", requireAuth, (req: Request, res: Response, next) => {
    upload.single("file")(req, res, (err) => {
        if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
            return res.status(400).json({ error: "File exceeds 10 MB limit" });
        }
        if (err) return res.status(400).json({ error: err.message });
        next();
    });
}, async (req: Request, res: Response) => {
    const callerId = (req as any).callerId as string;
    if (callerId !== req.params.id) return res.status(403).json({ error: "Forbidden" });

    if (!req.file) return res.status(400).json({ error: "file is required" });
    const { title } = req.body;
    if (!title) return res.status(400).json({ error: "title is required" });

    try {
        const memo = await MemoService.createFileMemo(req.params.id, title, req.file);
        res.status(201).json(memo);
    } catch (e) {
        console.error("[Memo] createFileMemo error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

// POST /api/patients/:id/memos/doctor — called by consultation composite to store MC/prescription
// No ownership check — caller must be authenticated (JWT verified), patient_id comes from path
router.post("/doctor", requireAuth, async (req: Request, res: Response) => {
    const title = req.body.title as string;
    const content = req.body.content as string;
    const record_type = req.body.record_type as string;
    const issued_by = req.body.issued_by as string;

    if (!title || !content || !record_type || !issued_by) {
        return res.status(400).json({ error: "title, content, record_type, and issued_by are required" });
    }
    if (!["mc", "prescription"].includes(record_type)) {
        return res.status(400).json({ error: "record_type must be 'mc' or 'prescription'" });
    }

    try {
        const memo = await MemoService.createDoctorRecord(String(req.params.id), title, content, record_type as "mc" | "prescription", String(issued_by));
        res.status(201).json(memo);
    } catch (e) {
        console.error("[Memo] createDoctorRecord error:", e);
        res.status(500).json({ error: "Internal server error" });
    }
});

export default router;
