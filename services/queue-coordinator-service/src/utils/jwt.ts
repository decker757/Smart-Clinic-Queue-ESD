/**
 * Decode a JWT payload without verifying the signature.
 *
 * Security model: All requests (including WebSocket upgrades) pass through
 * the API gateway before reaching this service. In local development, Kong's
 * JWT plugin validates the RS256 signature against the BetterAuth JWKS public
 * key (see kong.yml). In AWS, the API Gateway JWT authorizer validates against
 * Cognito's JWKS endpoint, and WebSocket traffic routed via CloudFront → ALB
 * carries tokens already validated by the frontend auth flow.
 *
 * This function therefore only decodes the payload to extract claims (sub,
 * role / custom:role) — signature verification is handled upstream.
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
