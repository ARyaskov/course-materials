<?php

declare(strict_types=1);

use App\Api\Event\RequestFinished;
use App\Infrastructure\Metrics\RecordHttpMetrics;
use App\Infrastructure\Log\LogRequestSummary;

return [
    RequestFinished::class => [
        [RecordHttpMetrics::class, '__invoke'],
        [LogRequestSummary::class, '__invoke'],
    ],
];
