import { Request, Response, NextFunction } from "express";
import * as crypto from "crypto";

// ─── JWKS public key (fetched once at startup) ────────────────────────────────
let publicKey: crypto.KeyObject | null = null;

export async function fetchPublicKey(retries = 10, delayMs = 3000): Promise<void> {
    const url = process.env.JWKS_URL ?? "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json";

    for (let attempt = 1; attempt <= retries; attempt++) {
        try {
            const res = await fetch(url);
            if (!res.ok) throw new Error(`HTTP ${res.status}`);

            const { keys } = await res.json() as { keys: Array<{ kty: string; n: string; e: string }> };
            const rsaKey = keys.find((k) => k.kty === "RSA");
            if (!rsaKey) throw new Error("No RSA key found in JWKS");

            publicKey = crypto.createPublicKey({ key: rsaKey as any, format: "jwk" });
            console.log("[Auth] RSA public key loaded from JWKS");
            return;
        } catch (err: any) {
            console.warn(`[Auth] JWKS fetch attempt ${attempt}/${retries} failed: ${err.message}`);
            if (attempt < retries) await new Promise((r) => setTimeout(r, delayMs));
        }
    }

    throw new Error(`Failed to fetch JWKS after ${retries} attempts`);
}

// ─── Middleware ───────────────────────────────────────────────────────────────
export function requireAuth(req: Request, res: Response, next: NextFunction) {
    const auth = req.headers.authorization;
    if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "Unauthorized" });

    const token = auth.slice(7);
    const parts = token.split(".");
    if (parts.length !== 3) return res.status(401).json({ error: "Unauthorized" });

    if (!publicKey) return res.status(503).json({ error: "Auth not ready" });

    // Verify RS256 signature
    const verified = crypto.verify(
        "sha256",
        Buffer.from(`${parts[0]}.${parts[1]}`),
        { key: publicKey, padding: crypto.constants.RSA_PKCS1_PADDING },
        Buffer.from(parts[2], "base64url")
    );
    if (!verified) return res.status(401).json({ error: "Unauthorized" });

    let payload: Record<string, unknown>;
    try {
        payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf-8"));
    } catch {
        return res.status(401).json({ error: "Unauthorized" });
    }

    if (payload.exp && typeof payload.exp === "number" && payload.exp < Math.floor(Date.now() / 1000)) {
        return res.status(401).json({ error: "Token expired" });
    }

    if (!payload.sub || typeof payload.sub !== "string") {
        return res.status(401).json({ error: "Unauthorized" });
    }

    (req as any).callerId = payload.sub;
    next();
}
