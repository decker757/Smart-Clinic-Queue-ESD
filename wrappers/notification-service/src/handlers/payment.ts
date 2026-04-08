import { sendSms } from "../notify/sms";
import { getPatientPhone } from "../notify/patient";

function formatAmount(amountCents?: number, currency?: string): string | null {
    if (amountCents == null) return null;
    const code = (currency ?? "SGD").toUpperCase();
    return `$${(amountCents / 100).toFixed(2)} ${code}`;
}

export async function handlePaymentLinkCreated(payload: any) {
    if (!payload?.patient_id || !payload?.payment_link) {
        console.warn("[payment.link_created] missing patient_id or payment_link, skipping");
        return;
    }

    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) {
        console.warn(`No phone for patient ${payload.patient_id}`);
        return;
    }

    const amount = formatAmount(payload.amount_cents, payload.currency);
    const lines = ["Your payment is ready."];
    if (amount) {
        lines.push(`Amount due: ${amount}.`);
    }
    lines.push(`Please complete your payment here: ${payload.payment_link}`);
    lines.push("Thank you for visiting SmartClinic.");

    await sendSms(phone, lines.join("\n"));
}

export async function handlePaymentCompleted(payload: any) {
    if (!payload?.patient_id) { console.warn("[payment.completed] missing patient_id, skipping"); return; }
    const phone = await getPatientPhone(payload.patient_id);
    if (!phone) { console.warn(`No phone for patient ${payload.patient_id}`); return; }
    await sendSms(phone, "Your payment has been received. Thank you for visiting SmartClinic!");
}
