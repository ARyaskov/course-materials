<?php

declare(strict_types=1);

namespace App\Api\Action\System;

use Psr\Http\Message\ResponseInterface;
use Psr\Log\LoggerInterface;
use Psr\SimpleCache\CacheInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Http\Status;

final readonly class HealthAction
{
    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
        private ConnectionInterface $db,
        private CacheInterface $cache,
        private LoggerInterface $logger,
        private string $version,
    ) {
    }

    public function __invoke(): ResponseInterface
    {
        $checks = [
            'db' => fn (): bool => $this->db->createCommand('SELECT 1')->queryScalar() === 1,
            'cache' => function (): bool {
                $key = 'health:' . bin2hex(random_bytes(4));
                $this->cache->set($key, 'ok', 10);

                return $this->cache->get($key) === 'ok';
            },
            'runtimeWritable' => fn (): bool => is_writable('/app/runtime'),
        ];

        $results = [];
        $healthy = true;

        foreach ($checks as $name => $check) {
            try {
                $ok = $check();
            } catch (\Throwable $e) {
                // причина — в лог, наружу только факт
                $this->logger->error('Проверка не прошла', [
                    'check' => $name, 'reason' => $e->getMessage(),
                ]);

                $ok = false;
            }

            $results[$name] = $ok ? 'ok' : 'fail';
            $healthy = $healthy && $ok;
        }

        return $this->responseFactory->createResponse(
            [
                'status' => $healthy ? 'ok' : 'degraded',
                'version' => $this->version,
                'php' => PHP_VERSION,
                'checks' => $results,
            ],
            // код важнее тела: по нему решает Docker и балансировщик
            $healthy ? Status::OK : Status::SERVICE_UNAVAILABLE,
        );
    }

    private function scheduleIsHealthy(): bool
    {
    foreach ($this->schedule->tasks() as $task) {
        $lastRun = $this->state->lastRun($task->name);

        // допускаем тройной интервал: разовый пропуск не тревожит
        if ($lastRun === null
            || $lastRun < (new \DateTimeImmutable())->modify(
                '-' . ($task->intervalSeconds * 3) . ' seconds')
        ) {
            return false;
        }
    }

    return true;
    }
}
