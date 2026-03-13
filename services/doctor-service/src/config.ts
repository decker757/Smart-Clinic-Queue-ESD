export const config = {
    httpPort: parseInt(process.env.PORT || "3004"),
    grpcPort: parseInt(process.env.GRPC_PORT || "50054"),
    databaseUrl: process.env.DATABASE_URL || "",
};