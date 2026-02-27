import { betterAuth } from "better-auth";
import { Pool } from "pg";
import { jwt } from "better-auth/plugins";

export const auth = betterAuth({
    database: new Pool({
        connectionString: process.env.DATABASE_URL,
    }),
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