/**
 * Activity Log business logic
 * Stores and retrieves logs via OutSystems REST API
 */

import { ClinicEvent, ActivityLogEntry } from "../model/ActivityLog";

const ACTIVITY_LOG_URL = "https://personal-cco9btns.outsystemscloud.com/ESDactivitylog/rest/ActivityLogAPI/logs";

export async function recordEvent(event: ClinicEvent): Promise<void> {
    try {
        const response = await fetch(ACTIVITY_LOG_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                RoutingKey: event.event_type,
                Payload: JSON.stringify(event.payload),
            }),
        });

        if (!response.ok) {
            throw new Error(`OutSystems returned ${response.status}`);
        }

        console.log(`[ActivityLog] Recorded ${event.event_type}`);
    } catch (e) {
        console.error(`[ActivityLog] Failed to record ${event.event_type}:`, e);
        throw e;
    }
}

export async function getPatientHistory(
    patient_id: string,
    limit: number = 50,
    offset: number = 0
): Promise<any[]> {
    try {
        const response = await fetch(ACTIVITY_LOG_URL);
        if (!response.ok) throw new Error(`OutSystems returned ${response.status}`);
        const logs = await response.json();
        return logs
            .filter((log: any) => {
                try {
                    const payload = JSON.parse(log.PayLoad);
                    return payload.patient_id === patient_id;
                } catch { return false; }
            })
            .slice(offset, offset + limit);
    } catch (e) {
        console.error("[ActivityLog] Failed to fetch logs:", e);
        throw e;
    }
}

export async function getAppointmentHistory(
    appointment_id: string,
    patient_id: string
): Promise<any[]> {
    try {
        const response = await fetch(ACTIVITY_LOG_URL);
        if (!response.ok) throw new Error(`OutSystems returned ${response.status}`);
        const logs = await response.json();
        return logs.filter((log: any) => {
            try {
                const payload = JSON.parse(log.PayLoad);
                return payload.appointment_id === appointment_id &&
                       payload.patient_id === patient_id;
            } catch { return false; }
        });
    } catch (e) {
        console.error("[ActivityLog] Failed to fetch logs:", e);
        throw e;
    }
}
