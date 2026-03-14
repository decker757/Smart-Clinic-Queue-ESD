export const config = {
    httpPort: parseInt(process.env.PORT || "3006"),
    grpcPort: parseInt(process.env.GRPC_PORT || "50055"),
    databaseUrl: process.env.DATABASE_URL || "",
};