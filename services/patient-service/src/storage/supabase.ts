import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const s3 = new S3Client({ region: process.env.AWS_REGION ?? "ap-southeast-1" });
const BUCKET = process.env.S3_BUCKET ?? "esd-smart-clinic-queue-prod-ap-southeast-1";

export async function uploadFile(
    patientId: string,
    filename: string,
    buffer: Buffer,
    mimetype: string
): Promise<string> {
    const key = `${patientId}/${Date.now()}-${filename}`;

    await s3.send(new PutObjectCommand({
        Bucket: BUCKET,
        Key: key,
        Body: buffer,
        ContentType: mimetype,
    }));

    return getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: key }), {
        expiresIn: 604800, // 7 days
    });
}
