import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

export async function handleDoctorUnavailable(payload: any) {
    if (!payload?.patient_id) { console.warn("[doctor.unavailable] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    const doctor = payload.doctor_name ?? "Your doctor";
    await sendSms(phone, `${doctor} is currently unavailable. Reply with:\n1 - Join generic queue\n2 - Wait for doctor\n3 - Reschedule to another day`);
}
