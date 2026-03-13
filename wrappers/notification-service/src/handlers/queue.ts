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
