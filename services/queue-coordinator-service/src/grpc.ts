import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";
import * as QueueService from "./service/Queue";

const PROTO_PATH = path.join(__dirname, "proto/queue.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});

const proto = grpc.loadPackageDefinition(packageDef) as any;

async function GetQueuePosition(call: any, callback: any){
    try{
        const response = await QueueService.getQueuePosition(call.request.appointment_id);
        callback(null, response);
    } catch (e: any){
        if (e.message === "Appointment not in queue")
            return callback({ code: grpc.status.NOT_FOUND, message: e.message });
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CheckIn(call: any, callback: any){
    try{
        const { appointment_id, caller_id } = call.request;
        const entry = await QueueService.checkIn(appointment_id, caller_id || undefined);
        callback(null, entry);
    } catch (e: any){
        if (e.message === "Forbidden")
            return callback({ code: grpc.status.PERMISSION_DENIED, message: e.message });
        if (e.message.startsWith("Cannot check in"))
            return callback({ code: grpc.status.FAILED_PRECONDITION, message: e.message });
        callback({ code: grpc.status.INTERNAL,  message: e.message});
    }
}

async function AddToQueue(call: any, callback: any){
    try{
        const entry = await QueueService.addToQueue(call.request);
        callback(null, entry);
    } catch(e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function RemoveFromQueue(call: any, callback: any){
    try{
        const entry = await QueueService.removeFromQueue(call.request.appointment_id);
        callback(null, entry);
    } catch (e: any){
        if (e.message === "Appointment not in queue")
            return callback({ code: grpc.status.NOT_FOUND, message: e.message });
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function MarkNoShow(call: any, callback: any){
    try{
        const entry = await QueueService.markNoShow(call.request.appointment_id);
        callback(null, entry);
    } catch(e : any){
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CompleteAppointment(call: any, callback: any) {
    try {
        const entry = await QueueService.completeAppointment(call.request.appointment_id);
        callback(null, entry);
    } catch (e: any) {
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

async function CallNext(call: any, callback: any) {
    try {
        const { session, doctor_id } = call.request;
        const entry = await QueueService.callNext(session, doctor_id || undefined);
        callback(null, entry);
    } catch (e: any) {
        if (e.message === "No waiting patients in queue")
            return callback({ code: grpc.status.NOT_FOUND, message: e.message });
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

export function startGrpcServer(){
    const server = new grpc.Server();
    server.addService(proto.queue.QueueService.service, {
        GetQueuePosition,
        CheckIn,
        AddToQueue,
        RemoveFromQueue,
        MarkNoShow,
        CompleteAppointment,
        CallNext,
    });

    const port = process.env.GRPC_PORT ?? "50052";
    server.bindAsync(
        `0.0.0.0:${port}`,
        grpc.ServerCredentials.createInsecure(),
        (err, actualPort) => {
            if (err) throw err;
            console.log(`[gRPC] Queue coordinator listening on :${actualPort}`);
        }
    );
}