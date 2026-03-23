import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

export async function handleCheckedIn(payload: any) {
    if (!payload?.patient_id) { console.warn("[queue.checked_in] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `You're checked in! Your queue number is ${payload.queue_number}.`);
}

export async function handleQueueCalled(payload: any) {
    if (!payload?.patient_id) { console.warn("[queue.called] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `It's your turn! Please proceed to the consultation room now.`);
}

export async function handleEtaAlert(payload: any) {
    if (!payload?.patient_id) { console.warn("[queue.eta_alert] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `Your turn is coming up soon. Are you on your way to the clinic?`);
}

export async function handleLateDetected(payload: any) {
    if (!payload?.patient_id) { console.warn("[queue.late_detected] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `You appear to be running late. Are you still coming? Reply YES to stay in queue or NO to cancel.`);
}

export async function handleDeprioritized(payload: any) {
    if (!payload?.patient_id) { console.warn("[queue.deprioritized] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `You've been moved to the back of the queue. Please proceed to the clinic when ready.`);
}

export async function handleRemoved(payload: any) {
    if (!payload?.patient_id) { console.warn("[queue.removed] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, `You have been removed from the queue. Please rebook if you still need to see a doctor.`);
}
