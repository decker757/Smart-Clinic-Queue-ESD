/**
 * Extract an error message from an API response body.
 *
 * All services now return { error: "..." } as the standard envelope.
 * Falls back to { detail: "..." } for any legacy responses.
 */
export function apiError(body, fallback = 'Something went wrong') {
  return body?.error ?? body?.detail ?? fallback
}
