<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use Psr\SimpleCache\CacheInterface;

/**
 * Теги через версии: сброс тега увеличивает его версию, и все ключи,
 * содержащие старую версию, становятся недостижимыми. Значения при этом
 * не удаляются — их вытеснит Redis по TTL.
 */
final readonly class TaggedCache
{
    public function __construct(private CacheInterface $cache)
    {
    }

    /**
     * @template T
     * @param list<string> $tags
     * @param callable(): T $compute
     * @return T
     */
    public function getOrSet(string $key, array $tags, callable $compute, int $ttl): mixed
    {
        $versionedKey = $this->versionedKey($key, $tags);
        $value = $this->cache->get($versionedKey);

        if ($value !== null) {
            return $value;
        }

        $value = $compute();
        $this->cache->set($versionedKey, $value, Ttl::jittered($ttl));

        return $value;
    }

    /** Сброс тега: одна операция инвалидирует любое число ключей. */
    public function invalidateTag(string $tag): void
    {
        $this->cache->set(
            'tag:' . $tag,
            // новая версия: старые ключи больше не собираются
            bin2hex(random_bytes(4)),
            ttl: 86400 * 30,
        );
    }

    /** @param list<string> $tags */
    private function versionedKey(string $key, array $tags): string
    {
        sort($tags);
        $versions = [];

        foreach ($tags as $tag) {
            $versions[] = $tag . '=' . ($this->cache->get('tag:' . $tag) ?? 'init');
        }

        return $key . '|' . hash('xxh128', implode(',', $versions));
    }
}
