import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

export async function handlePaymentCompleted(payload: any) {
    if (!payload?.patient_id) { console.warn("[payment.completed] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, "Your payment has been received. Thank you for visiting SmartClinic!");
}
