/**
 * In-memory deduplication cache for notification events.
 *
 * Prevents duplicate SMSes when the same event is delivered more than once
 * for the same appointment — e.g. queue.removed fired by both an explicit
 * patient confirmation and the TTL dead-letter queue.
 *
 * Entries expire after TTL_MS so memory doesn't grow unboundedly.
 */

const TTL_MS = 10 * 60 * 1000; // 10 minutes — covers the 5-min TTL window with margin

const seen = new Map<string, number>(); // key → expiry timestamp

// Sweep expired entries every 5 minutes
setInterval(() => {
    const now = Date.now();
    for (const [key, expiry] of seen) {
        if (now >= expiry) seen.delete(key);
    }
}, 5 * 60 * 1000).unref(); // .unref() so this timer doesn't keep the process alive

/**
 * Returns true if this (appointmentId, eventType) pair has NOT been seen
 * recently, and records it so subsequent calls return false.
 */
export function dedup(appointmentId: string, eventType: string): boolean {
    const key = `${eventType}:${appointmentId}`;
    const now = Date.now();
    const expiry = seen.get(key);
    if (expiry != null && expiry > now) {
        console.warn(`[dedup] Dropping duplicate ${eventType} for appointment ${appointmentId}`);
        return false;
    }
    // Lazy-delete expired entries on access to bound Map size between sweeps
    if (expiry != null) seen.delete(key);
    seen.set(key, now + TTL_MS);
    return true;
}
