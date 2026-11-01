package dev.atrium.infrastructure.cache

import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/** Простейший in-process кэш «ключ → значение» с TTL. В главе 12 заменяется на Caffeine. */
class CachedLookup<K : Any, V : Any>(
    private val ttl: Duration,
    private val load: suspend (K) -> V?,
) {
    private val entries = ConcurrentHashMap<K, Entry<V>>()

    suspend fun get(key: K, now: Instant): V? {
        entries[key]?.takeIf { it.expiresAt > now }?.let { return it.value }
        val value = load(key) ?: return null
        entries[key] = Entry(value, now + ttl)
        return value
    }

    fun invalidate(key: K) {
        entries.remove(key)
    }

    private class Entry<V>(val value: V, val expiresAt: Instant)
}
