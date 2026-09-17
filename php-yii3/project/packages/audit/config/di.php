<?php

declare(strict_types=1);

use HelpDesk\Audit\{AuditRepositoryInterface, DbAuditRepository, AuditLogger};
use Yiisoft\Definitions\Reference;

return [
    AuditRepositoryInterface::class => DbAuditRepository::class,

    AuditLogger::class => [
        'class' => AuditLogger::class,
        '__construct()' => [
            'repository' => Reference::to(AuditRepositoryInterface::class),
        ],
    ],
];
