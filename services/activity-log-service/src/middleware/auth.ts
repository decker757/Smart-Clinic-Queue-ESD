import { Request, Response, NextFunction } from "express";

function decodeJwtPayload(token: string): Record<string, unknown> | null {
    try {
        const parts = token.split(".");
        if (parts.length !== 3) return null;
        return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf-8"));
    } catch {
        return null;
    }
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
    const auth = req.headers.authorization;
    if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "Unauthorized" });
    const payload = decodeJwtPayload(auth.slice(7));
    if (!payload?.sub) return res.status(401).json({ error: "Unauthorized" });
    (req as any).callerId = payload.sub as string;
    next();
}
