import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";
import * as PatientService from "./service/Patient";
import * as HistoryService from "./service/History";
import * as MemoService from "./service/Memo";

const PROTO_PATH = path.join(__dirname, "proto/patient.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});
const proto = grpc.loadPackageDefinition(packageDef) as any;

// ─── Patient handlers ────────────────────────────────────────────────────────

function serializePatient(patient: PatientService.Patient) {
    return {
        ...patient,
        phone: patient.phone ?? "",
        dob: patient.dob ? new Date(patient.dob as any).toISOString().slice(0, 10) : "",
        nric: patient.nric ?? "",
        gender: patient.gender ?? "",
        allergies: patient.allergies ?? [],
        created_at: patient.created_at.toISOString(),
        updated_at: patient.updated_at.toISOString(),
    };
}

async function GetPatient(call: any, callback: any) {
    try {
        const patient = await PatientService.getPatient(call.request.id);
        if (!patient) return callback({ code: grpc.status.NOT_FOUND, message: "Patient not found" });
        callback(null, serializePatient(patient));
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CreatePatient(call: any, callback: any) {
    try {
        const patient = await PatientService.createPatient(call.request.id, call.request);
        callback(null, serializePatient(patient));
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function UpdatePatient(call: any, callback: any) {
    try {
        const patient = await PatientService.updatePatient(call.request.id, call.request);
        if (!patient) return callback({ code: grpc.status.NOT_FOUND, message: "Patient not found" });
        callback(null, serializePatient(patient));
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

// ─── History handlers ────────────────────────────────────────────────────────

async function GetHistory(call: any, callback: any) {
    try {
        const entries = await HistoryService.getHistory(call.request.patient_id);
        callback(null, {
            entries: entries.map(e => ({
                ...e,
                diagnosed_at: e.diagnosed_at ?? "",
                notes: e.notes ?? "",
                created_at: e.created_at.toISOString(),
            })),
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function AddHistory(call: any, callback: any) {
    try {
        const { patient_id, diagnosis, diagnosed_at, notes, appointment_id } = call.request;
        const entry = await HistoryService.addHistory(patient_id, {
            diagnosis,
            diagnosed_at: diagnosed_at || undefined,
            notes: notes || undefined,
            appointment_id: appointment_id || undefined,
        });
        callback(null, {
            ...entry,
            diagnosed_at: entry.diagnosed_at ?? "",
            notes: entry.notes ?? "",
            created_at: entry.created_at.toISOString(),
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

// ─── Memo handlers ───────────────────────────────────────────────────────────

async function GetMemos(call: any, callback: any) {
    try {
        const memos = await MemoService.getMemos(call.request.patient_id);
        callback(null, {
            memos: memos.map(m => ({
                ...m,
                content: m.content ?? "",
                file_url: m.file_url ?? "",
                file_type: m.file_type ?? "",
                issued_by: m.issued_by ?? "",
                appointment_id: m.appointment_id ?? "",
                created_at: m.created_at.toISOString(),
            })),
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CreateTextMemo(call: any, callback: any) {
    try {
        const { patient_id, title, content } = call.request;
        const memo = await MemoService.createTextMemo(patient_id, title, content);
        callback(null, {
            ...memo,
            content: memo.content ?? "",
            file_url: memo.file_url ?? "",
            file_type: memo.file_type ?? "",
            issued_by: memo.issued_by ?? "",
            created_at: memo.created_at.toISOString(),
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CreateFileMemo(call: any, callback: any) {
    try {
        const { patient_id, title, file_data, original_name, mimetype } = call.request;
        const file: Express.Multer.File = {
            buffer: Buffer.from(file_data),
            originalname: original_name,
            mimetype,
            fieldname: "file",
            encoding: "7bit",
            size: file_data.length,
            destination: "",
            filename: "",
            path: "",
            stream: null as any,
        };
        const memo = await MemoService.createFileMemo(patient_id, title, file);
        callback(null, {
            ...memo,
            content: memo.content ?? "",
            file_url: memo.file_url ?? "",
            file_type: memo.file_type ?? "",
            issued_by: memo.issued_by ?? "",
            created_at: memo.created_at.toISOString(),
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CreateDoctorRecord(call: any, callback: any) {
    try {
        const { patient_id, title, content, record_type, issued_by, appointment_id } = call.request;
        const memo = await MemoService.createDoctorRecord(patient_id, title, content, record_type, issued_by, appointment_id || undefined);
        callback(null, {
            ...memo,
            content: memo.content ?? "",
            file_url: memo.file_url ?? "",
            file_type: memo.file_type ?? "",
            issued_by: memo.issued_by ?? "",
            appointment_id: memo.appointment_id ?? "",
            created_at: memo.created_at.toISOString(),
        });
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

// ─── Server ──────────────────────────────────────────────────────────────────

export function startGrpcServer() {
    const server = new grpc.Server();
    server.addService(proto.patient.PatientService.service, {
        GetPatient,
        CreatePatient,
        UpdatePatient,
        GetHistory,
        AddHistory,
        GetMemos,
        CreateTextMemo,
        CreateFileMemo,
        CreateDoctorRecord,
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
