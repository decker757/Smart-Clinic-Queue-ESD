/**
 * Decode a JWT payload without verifying the signature.
 * Safe because Kong has already validated the token before routing to this service.
 * We only decode to extract the caller's identity (sub claim).
 */
export function decodeJwtPayload(token: string): Record<string, unknown> | null {
    try {
        const parts = token.split(".");
        if (parts.length !== 3) return null;
        return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf-8"));
    } catch {
        return null;
    }
}

/**
 * Extract the caller's user ID from a Bearer token header value.
 * Returns null if the header is missing, malformed, or payload has no `sub`.
 */
export function callerIdFromAuthHeader(authHeader: string | undefined): string | null {
    if (!authHeader?.startsWith("Bearer ")) return null;
    const token = authHeader.slice(7);
    const payload = decodeJwtPayload(token);
    return (payload?.sub as string) ?? null;
}
