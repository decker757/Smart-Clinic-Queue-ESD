import path from "path";
import * as grpc from "@grpc/grpc-js";
import * as protoLoader from "@grpc/proto-loader";
import { getTravelMinutes } from "./maps/googleMaps";

const PROTO_PATH = path.join(__dirname, "proto/eta.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
});
const proto = grpc.loadPackageDefinition(packageDef) as any;

async function GetTravelTime(call: any, callback: any) {
    const { origin_lat, origin_lng, dest_lat, dest_lng } = call.request;

    if (
        origin_lat == null || origin_lng == null ||
        dest_lat   == null || dest_lng   == null
    ) {
        return callback({ code: grpc.status.INVALID_ARGUMENT, message: "All coordinates are required" });
    }

    try {
        const { minutes, mode, source } = await getTravelMinutes(
            Number(origin_lat),
            Number(origin_lng),
            Number(dest_lat),
            Number(dest_lng)
        );
        console.log(`[ETA] ${origin_lat},${origin_lng} → ${dest_lat},${dest_lng} = ${minutes} min via ${mode} (${source})`);
        callback(null, { travel_minutes: minutes, mode, source });
    } catch (e: any) {
        console.error("[ETA] GetTravelTime error:", e.message);
        callback({ code: grpc.status.INTERNAL, message: e.message });
    }
}

export function startGrpcServer() {
    const server = new grpc.Server();
    server.addService(proto.eta.ETAService.service, { GetTravelTime });

    const port = process.env.GRPC_PORT ?? "50054";
    server.bindAsync(
        `0.0.0.0:${port}`,
        grpc.ServerCredentials.createInsecure(),
        (err, actualPort) => {
            if (err) throw err;
            console.log(`[gRPC] ETA service listening on :${actualPort}`);
        }
    );
}
