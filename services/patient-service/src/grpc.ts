import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";
import * as PatientService from "./service/Patient";

const PROTO_PATH = path.join(__dirname, "proto/patient.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});
const proto = grpc.loadPackageDefinition(packageDef) as any;

async function GetPatient(call: any, callback: any) {
    try {
        const patient = await PatientService.getPatient(call.request.id);
        if (!patient) return callback({ code: grpc.status.NOT_FOUND, message: "Patient not found" });
        callback(null, {
            ...patient,
            dob: patient.dob ?? "",
            phone: patient.phone ?? "",
            nric: patient.nric ?? "",
            allergies: patient.allergies ?? [],
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CreatePatient(call: any, callback: any) {
    try {
        const patient = await PatientService.createPatient(call.request.id, call.request);
        callback(null, { ...patient, dob: patient.dob ?? "", phone: patient.phone ?? "", nric: patient.nric ?? "" });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function UpdatePatient(call: any, callback: any) {
    try {
        const patient = await PatientService.updatePatient(call.request.id, call.request);
        if (!patient) return callback({ code: grpc.status.NOT_FOUND, message: "Patient not found" });
        callback(null, { ...patient, dob: patient.dob ?? "", phone: patient.phone ?? "", nric: patient.nric ?? "" });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

export function startGrpcServer() {
    const server = new grpc.Server();
    server.addService(proto.patient.PatientService.service, {
        GetPatient,
        CreatePatient,
        UpdatePatient,
    });

    const port = process.env.GRPC_PORT ?? "50053";
    server.bindAsync(
        `0.0.0.0:${port}`,
        grpc.ServerCredentials.createInsecure(),
        (err, actualPort) => {
            if (err) throw err;
            console.log(`[gRPC] Patient service listening on :${actualPort}`);
        }
    );
}
