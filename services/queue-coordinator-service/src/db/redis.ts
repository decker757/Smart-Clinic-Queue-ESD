import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL || "redis://localhost:6379", {
    lazyConnect: false,
    maxRetriesPerRequest: 3,
});

redis.on("connect", () => console.log("[Redis] connected"));
redis.on("error", (err) => console.error("[Redis] error:", err));

// Verify Redis is reachable at startup so misconfigurations fail fast
redis.ping().then(() => {
    console.log("[Redis] ping OK — connection verified");
}).catch((err) => {
    console.error("[Redis] startup ping failed:", err.message);
});

export default redis;
