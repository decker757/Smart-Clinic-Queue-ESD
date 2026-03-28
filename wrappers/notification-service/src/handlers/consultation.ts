import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

export async function handleConsultationCompleted(payload: any) {
    if (!payload?.patient_id) { console.warn("[consultation.completed] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    if (payload.payment_link) {
        await sendSms(phone, `Your consultation is complete. Please complete your payment here: ${payload.payment_link}`);
    } else {
        await sendSms(phone, `Your consultation is complete. Thank you for visiting SmartClinic.`);
    }
}
