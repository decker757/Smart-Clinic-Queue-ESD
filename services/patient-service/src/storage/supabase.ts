import path from "path";
import fs from "fs";

// ─── Local-first file storage ───────────────────────────────────────────────
// In local Docker mode there is no real S3 bucket. Files are written to a
// local directory and served via the Express static middleware mounted at
// /uploads in the patient-service HTTP server.
//
// When running on AWS with valid credentials the S3 path is used instead.

const USE_S3 =
    process.env.AWS_ACCESS_KEY_ID &&
    process.env.AWS_ACCESS_KEY_ID !== "local-dev-key" &&
    process.env.S3_BUCKET;

// ─── S3 path (production / AWS) ─────────────────────────────────────────────
async function uploadToS3(
    patientId: string,
    filename: string,
    buffer: Buffer,
    mimetype: string,
): Promise<string> {
    const { S3Client, PutObjectCommand, GetObjectCommand } = await import("@aws-sdk/client-s3");
    const { getSignedUrl } = await import("@aws-sdk/s3-request-presigner");
    const s3 = new S3Client({ region: process.env.AWS_REGION ?? "ap-southeast-1" });
    const BUCKET = process.env.S3_BUCKET!;
    const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, "_").substring(0, 255);
    const key = `${patientId}/${Date.now()}-${safeName}`;

    await s3.send(
        new PutObjectCommand({ Bucket: BUCKET, Key: key, Body: buffer, ContentType: mimetype }),
    );

    return getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: key }), {
        expiresIn: 604800,
    });
}

// ─── Local path (Docker Compose) ────────────────────────────────────────────
const LOCAL_DIR = path.resolve(__dirname, "../../uploads");

function ensureDir(dir: string) {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

async function uploadLocally(
    patientId: string,
    filename: string,
    buffer: Buffer,
    _mimetype: string,
): Promise<string> {
    const patientDir = path.join(LOCAL_DIR, patientId);
    ensureDir(patientDir);
    const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, "_").substring(0, 255);
    const uniqueName = `${Date.now()}-${safeName}`;
    const filePath = path.join(patientDir, uniqueName);
    fs.writeFileSync(filePath, buffer);

    // Return a relative path served via Kong → patient-service static middleware.
    // The frontend prepends VITE_API_BASE_URL (e.g. http://localhost:8000) so
    // the browser can reach the file through Kong's /api/patients/* route.
    return `/api/patients/uploads/${patientId}/${uniqueName}`;
}

// ─── Public API ─────────────────────────────────────────────────────────────
export async function uploadFile(
    patientId: string,
    filename: string,
    buffer: Buffer,
    mimetype: string,
): Promise<string> {
    if (USE_S3) {
        return uploadToS3(patientId, filename, buffer, mimetype);
    }
    return uploadLocally(patientId, filename, buffer, mimetype);
}

export { LOCAL_DIR };
