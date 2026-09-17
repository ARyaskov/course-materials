<?php

declare(strict_types=1);

use App\Domain\Report\SummaryRepositoryInterface;
use App\Infrastructure\Report\{CachedSummaryRepository, DbSummaryRepository};
use Yiisoft\Definitions\Reference;

return [
    SummaryRepositoryInterface::class => [
        'class' => CachedSummaryRepository::class,
        '__construct()' => ['inner' => Reference::to(DbSummaryRepository::class)],
    ],
];
