import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_KEY!
);

const BUCKET = process.env.SUPABASE_BUCKET ?? "patient-memos";

export async function uploadFile(
    patientId: string,
    filename: string,
    buffer: Buffer,
    mimetype: string
): Promise<string> {
    const path = `${patientId}/${Date.now()}-${filename}`;
    const { error } = await supabase.storage
        .from(BUCKET)
        .upload(path, buffer, { contentType: mimetype });

    if (error) throw new Error(`Upload failed: ${error.message}`);

    const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
    return data.publicUrl;
}
