import { betterAuth } from "better-auth";
import { Pool } from "pg";
import { jwt } from "better-auth/plugins";

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

pool.on("connect", (client) => {
    client.query("SET search_path TO betterauth");
});

export const auth = betterAuth({
    database: pool,
    emailAndPassword: {
        enabled: true,
    },
    plugins: [
        jwt({
            jwt: {
                issuer: "smart-clinic",
                audience: "smart-clinic-services",
                expirationTime: "1h",
            },
        }),
    ],
});