import twilio from "twilio";

const TWILIO_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const FROM = process.env.TWILIO_PHONE_NUMBER;

if (!TWILIO_SID || !TWILIO_TOKEN || !FROM) {
    console.error("[SMS] Missing required env vars: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER");
    process.exit(1);
}

const client = twilio(TWILIO_SID, TWILIO_TOKEN);

export async function sendSms(to: string, message: string): Promise<void>{
    await client.messages.create({to, from: FROM, body: message});
    console.log(`[SMS] Sent to ${to}: ${message}`);
}