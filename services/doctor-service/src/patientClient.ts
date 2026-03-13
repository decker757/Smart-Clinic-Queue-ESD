import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";

const PROTO_PATH = path.join(__dirname, "proto/patient.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});

const proto = grpc.loadPackageDefinition(packageDef) as any;

const PATIENT_SERVICE_URL = process.env.PATIENT_SERVICE_URL || "patient-service:50053";

const client = new proto.patient.PatientService(
    PATIENT_SERVICE_URL,
    grpc.credentials.createInsecure()
);

export function getPatient(id: string): Promise<any> {
    return new Promise((resolve, reject) => {
        client.GetPatient({ id }, (err: any, response: any) => {
            if (err) reject(err);
            else resolve(response);
        });
    });
}
