<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use Psr\SimpleCache\CacheInterface;
use Yiisoft\Cache\ArrayCache;
use Yiisoft\Cache\File\FileCache;
use Yiisoft\Cache\Redis\RedisCache;

final readonly class CacheFactory
{
    public function __construct(
        private string $driver,
        private string $redisUri,
        private string $filePath,
    ) {
    }

    public function create(): CacheInterface
    {
        return match ($this->driver) {
            'redis' => new RedisCache($this->redisClient()),
            'file' => new FileCache($this->filePath),
            'array' => new ArrayCache(),
            default => throw new \InvalidArgumentException(
                "Неизвестный драйвер кеша: {$this->driver}",
            ),
        };
    }

    private function redisClient(): \Predis\ClientInterface
    {
        return new \Predis\Client($this->redisUri);
    }
}
