<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use Psr\Http\Message\ResponseInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;

/**
 * Отдаёт данные нужной ФОРМЫ до готовности реализации.
 * Клиенты пишутся против неё; замена на настоящий обработчик —
 * одна строка в routes.php, контракт при этом не меняется.
 */
final readonly class StubListTicketsAction
{
    public function __construct(private DataResponseFactoryInterface $responseFactory)
    {
    }

    public function __invoke(): ResponseInterface
    {
        return $this->responseFactory->createResponse([
            'items' => [
                [
                    'id' => 1042,
                    'title' => 'Не открывается VPN',
                    'status' => 'open',
                    'priority' => 'high',
                    'assigneeId' => null,
                    'createdAt' => '2026-09-06T09:14:22+00:00',
                    'slaDeadline' => '2026-09-06T17:14:22+00:00',
                ],
            ],
            'meta' => ['total' => 1, 'limit' => 20, 'offset' => 0, 'hasMore' => false],
        ]);
    }
}
