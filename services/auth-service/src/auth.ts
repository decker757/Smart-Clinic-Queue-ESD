import { betterAuth } from "better-auth";
import { Pool } from "pg";
import { jwt, bearer } from "better-auth/plugins";

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

pool.on("connect", (client) => {
    client.query("SET search_path TO betterauth");
});

// Allowed browser origins — comma-separated list via env var
// e.g. CORS_ORIGIN=http://localhost:5173,https://your-frontend.com
export const trustedOrigins = (process.env.CORS_ORIGIN ?? "http://localhost:5173")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);

export const auth = betterAuth({
    database: pool,
    trustedOrigins,
    emailAndPassword: {
        enabled: true,
    },
    user: {
        additionalFields: {
            role: {
                type: "string",
                defaultValue: "patient",
            },
        },
    },
    plugins: [
        bearer(),
        jwt({
            jwks: {
                keyPairConfig: {
                    alg: "RS256",
                },
                disablePrivateKeyEncryption: true,
            },
            jwt: {
                issuer: "smart-clinic",
                audience: "smart-clinic-services",
                expirationTime: "1h",
                definePayload: async ({ user }) => ({
                    role: (user as any).role ?? "patient",
                    name: user.name,
                }),
            },
        }),
    ],
});