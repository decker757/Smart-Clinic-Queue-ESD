import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";

const PROTO_PATH = path.join(__dirname, "../proto/patient.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});
const proto = grpc.loadPackageDefinition(packageDef) as any;

const patientClient = new proto.patient.PatientService(
    process.env.PATIENT_SERVICE_GRPC_URL ?? "patient-service:50053",
    grpc.credentials.createInsecure()
);

// Close the gRPC channel on process shutdown to prevent connection pool exhaustion
function closeClient() {
    patientClient.close();
    console.log("[gRPC] Patient client connection closed");
}
process.on("SIGTERM", closeClient);
process.on("SIGINT", closeClient);

export async function getPatientPhone(patient_id: string): Promise<string | null> {
    return new Promise((resolve) => {
        patientClient.GetPatient({ id: patient_id }, (err: any, response: any) => {
            if (err || !response?.phone) {
                console.warn(`[Patient] Could not get phone for ${patient_id}:`, err?.message);
                resolve(null);
                return;
            }
            resolve(response.phone);
        });
    });
}
