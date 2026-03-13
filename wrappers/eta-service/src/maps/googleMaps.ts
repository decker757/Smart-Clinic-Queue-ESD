const API_KEY = process.env.GOOGLE_MAPS_API_KEY;

async function queryMode(
    originLat: number,
    originLng: number,
    destLat: number,
    destLng: number,
    mode: string
): Promise<{ minutes: number; mode: string } | null> {
    const url =
        `https://maps.googleapis.com/maps/api/directions/json` +
        `?origin=${originLat},${originLng}` +
        `&destination=${destLat},${destLng}` +
        `&mode=${mode}` +
        `&key=${API_KEY}`;

    try {
        const res = await fetch(url);
        if (!res.ok) return null;
        const data = await res.json() as any;
        if (data.status !== "OK") return null;
        return { minutes: Math.ceil(data.routes[0].legs[0].duration.value / 60), mode };
    } catch {
        return null;
    }
}

export async function getTravelMinutes(
    originLat: number,
    originLng: number,
    destLat: number,
    destLng: number
): Promise<{ minutes: number; mode: string; source: string }> {
    // ── Stub: return fixed 15 mins when no API key is configured ──────────────
    if (!API_KEY || API_KEY === "your-google-maps-api-key-here") {
        console.warn("[ETA] No Google Maps API key — returning stub travel time");
        return { minutes: 15, mode: "stub", source: "stub" };
    }

    // ── Real: query transit + walking in parallel, take the shorter one ───────
    const [transit, walking] = await Promise.all([
        queryMode(originLat, originLng, destLat, destLng, "transit"),
        queryMode(originLat, originLng, destLat, destLng, "walking"),
    ]);

    console.log(`[ETA] transit=${transit?.minutes}min walking=${walking?.minutes}min`);

    const best = [transit, walking]
        .filter((r): r is { minutes: number; mode: string } => r !== null)
        .sort((a, b) => a.minutes - b.minutes)[0];

    if (best == null) throw new Error("Google Maps returned no valid routes");

    return { minutes: best.minutes, mode: best.mode, source: "google_maps" };
}
