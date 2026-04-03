import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

export async function handleConsultationCompleted(payload: any) {
    if (!payload?.patient_id) { console.warn("[consultation.completed] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }

    // Build a rich message with all consultation details
    const lines: string[] = ["Your consultation is complete."];

    if (payload.diagnosis) {
        lines.push(`Diagnosis: ${payload.diagnosis}.`);
    }
    if (payload.prescribed_medication) {
        lines.push(`Medication: ${payload.prescribed_medication}. Please collect from the pharmacy.`);
    }
    if (payload.mc_issued) {
        lines.push("A Medical Certificate has been issued — you can view it in your patient records.");
    }
    if (payload.payment_link) {
        lines.push(`Please complete your payment here: ${payload.payment_link}`);
    }

    lines.push("Thank you for visiting SmartClinic.");

    await sendSms(phone, lines.join("\n"));
}
