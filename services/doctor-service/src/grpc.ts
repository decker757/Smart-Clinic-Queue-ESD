import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";
import * as DoctorService from "./service/Doctor";
import { config } from "./config";

const PROTO_PATH = path.join(__dirname, "proto/doctor.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});

const grpcObject = grpc.loadPackageDefinition(packageDef) as any;
const doctorPackage = grpcObject.doctor;

function formatDoctor(d: any) {
    return {
        id: d.id,
        name: d.name,
        specialisation: d.specialisation ?? "",
        contact: d.contact ?? "",
        created_at: d.created_at?.toISOString() ?? "",
    };
}

function formatSlot(s: any) {
    return {
        id: s.id,
        doctor_id: s.doctor_id,
        start_time: s.start_time?.toISOString() ?? "",
        end_time: s.end_time?.toISOString() ?? "",
        status: s.status,
    };
}

const handlers = {
    GetDoctor: async (call: any, callback: any) => {
        try {
            const doctor = await DoctorService.getDoctorById(call.request.doctor_id);
            callback(null, formatDoctor(doctor));
        } catch (e: any) {
            callback({ code: grpc.status.NOT_FOUND, message: e.message });
        }
    },

    GetDoctorSlots: async (call: any, callback: any) => {
        try {
            const slots = await DoctorService.getDoctorSlots(call.request.doctor_id);
            callback(null, { slots: slots.map(formatSlot) });
        } catch (e: any) {
            callback({ code: grpc.status.INTERNAL, message: e.message });
        }
    },

    UpdateSlotStatus: async (call: any, callback: any) => {
        try {
            const slot = await DoctorService.updateSlotStatus(call.request.slot_id, call.request.status);
            callback(null, formatSlot(slot));
        } catch (e: any) {
            callback({ code: grpc.status.NOT_FOUND, message: e.message });
        }
    },

    ListDoctors: async (call: any, callback: any) => {
        try {
            const doctors = await DoctorService.listDoctors();
            callback(null, { doctors: doctors.map(formatDoctor) });
        } catch (e: any) {
            callback({ code: grpc.status.INTERNAL, message: e.message });
        }
    },
};

export function startGrpcServer(): void {
    const server = new grpc.Server();
    server.addService(doctorPackage.DoctorService.service, handlers);
    server.bindAsync(
        `0.0.0.0:${config.grpcPort}`,
        grpc.ServerCredentials.createInsecure(),
        (err, port) => {
            if (err) {
                console.error("[gRPC] Failed to start:", err);
                process.exit(1);
            }
            console.log(`[gRPC] Doctor service running on port ${port}`);
        }
    );
}