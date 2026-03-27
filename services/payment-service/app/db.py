import asyncpg
from app.config import settings

_pool: asyncpg.Pool | None = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        # Strip ?options= — asyncpg doesn't support it, and Supavisor pooler strips
        # SET search_path anyway. Use explicit payments.payments in all queries instead.
        url = settings.DATABASE_URL.split("?")[0]
        _pool = await asyncpg.create_pool(url, min_size=1, max_size=5)
    return _pool


async def close_pool():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
