import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

function formatSgt(iso: string): string {
    const d = new Date(iso);
    return d.toLocaleString("en-SG", {
        timeZone: "Asia/Singapore",
        weekday: "short",
        day: "numeric",
        month: "short",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
        hour12: true,
    }) + " SGT";
}

export async function handleAppointmentBooked(payload: any) {
    if (!payload?.patient_id) { console.warn("[appointment.booked] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    const time = payload.start_time ? formatSgt(payload.start_time) : `${payload.session} session`;
    const doctor = payload.doctor_name ? ` with ${payload.doctor_name}` : "";
    await sendSms(phone, `Your appointment has been confirmed for ${time}${doctor}. Please check in 5 mins before your turn.`);
}

export async function handleAppointmentCancelled(payload: any) {
    if (!payload?.patient_id) { console.warn("[appointment.cancelled] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `Your appointment has been cancelled.`);
}

export async function handleAppointmentCreated(payload: any) {
    if (!payload?.patient_id) { console.warn("[appointment.created] missing patient_id, skipping"); return; }
    // triggered when a reshuffle in queue happens - patient moved to generic queue
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `You have been moved to the generic queue. We'll notify you when it is your turn.`);
}
