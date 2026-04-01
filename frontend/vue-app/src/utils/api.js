/**
 * Extract an error message from an API response body.
 *
 * Node.js services return { error: "..." }, Python/FastAPI returns { detail: "..." }.
 * This helper normalises both formats so callers don't need to check each field.
 */
export function apiError(body, fallback = 'Something went wrong') {
  return body?.detail ?? body?.error ?? fallback
}
