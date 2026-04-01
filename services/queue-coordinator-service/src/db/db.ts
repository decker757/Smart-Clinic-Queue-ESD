import { Pool } from "pg";

if (!process.env.DATABASE_URL) {
    console.error("[DB] DATABASE_URL is not set");
    process.exit(1);
}

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

export default pool;