import twilio from "twilio";

const SMS_ENABLED = process.env.SMS_ENABLED !== "false"; // default: enabled

const TWILIO_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const FROM = process.env.TWILIO_PHONE_NUMBER;

let client: ReturnType<typeof twilio> | null = null;

if (SMS_ENABLED) {
    if (!TWILIO_SID || !TWILIO_TOKEN || !FROM) {
        console.warn("[SMS] Missing Twilio env vars (TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER) — falling back to dry-run mode. Set SMS_ENABLED=false to suppress this warning.");
    } else {
        client = twilio(TWILIO_SID, TWILIO_TOKEN);
        console.log("[SMS] Twilio client initialised");
    }
} else {
    console.log("[SMS] Disabled (SMS_ENABLED=false) — messages will be logged but not sent");
}

export async function sendSms(to: string, message: string): Promise<void> {
    if (!SMS_ENABLED || !client) {
        console.log(`[SMS][DRY-RUN] → ${to}: ${message}`);
        return;
    }
    await client.messages.create({ to, from: FROM!, body: message });
    console.log(`[SMS] Sent to ${to}: ${message}`);
}
