<?php

declare(strict_types=1);

namespace App\Infrastructure\Metrics;

use App\Api\Event\RequestFinished;
use Yiisoft\Router\CurrentRoute;

final readonly class RecordHttpMetrics
{
    public function __construct(
        private MetricsInterface $metrics,
        private CurrentRoute $currentRoute,
    ) {
    }

    public function __invoke(RequestFinished $event): void
    {
        $this->metrics->histogram('http_request_duration_ms', $event->durationMs, [
            // имя маршрута, а не путь: кардинальность не растёт с числом заявок
            'route' => $this->currentRoute->getName() ?? 'unknown',
            'method' => $event->request->getMethod(),
            'status' => (string) $event->response->getStatusCode(),
        ]);
    }
}
