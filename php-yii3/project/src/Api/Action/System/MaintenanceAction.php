<?php

declare(strict_types=1);

namespace App\Api\Action\System;

use Psr\Http\Message\ResponseInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;

final readonly class MaintenanceAction
{
    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
        private int $retryAfterSeconds = 120,
    ) {
    }

    public function __invoke(): ResponseInterface
    {
        return $this->responseFactory
            ->createResponse(
                ['error' => ['type' => 'maintenance',
                             'message' => 'Сервис временно недоступен.']],
                Status::SERVICE_UNAVAILABLE,
            )
            // клиент узнаёт, когда повторить, и не бьётся в закрытую дверь
            ->withHeader('Retry-After', (string) $this->retryAfterSeconds);
    }
}
