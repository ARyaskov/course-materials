<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Domain\Ticket\TicketRepositoryInterface;
use App\Domain\Ticket\TicketStatus;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;

final readonly class ListTicketsAction
{
    private const MAX_LIMIT = 100;

    public function __construct(
        private TicketRepositoryInterface $tickets,
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(ServerRequestInterface $request): ResponseInterface
    {
        $query = $request->getQueryParams();

        // tryFrom, а не from: неизвестный статус не должен ронять запрос
        $status = isset($query['status'])
            ? TicketStatus::tryFrom((string) $query['status'])
            : null;

        $limit = min(max((int) ($query['limit'] ?? 20), 1), self::MAX_LIMIT);
        $offset = max((int) ($query['offset'] ?? 0), 0);

        $tickets = $this->tickets->findAll($status, $limit, $offset);

        return $this->responseFactory->createResponse([
            'items' => array_map(TicketView::fromEntity(...), $tickets),
            'meta' => [
                'total' => $this->tickets->countAll($status),
                'limit' => $limit,
                'offset' => $offset,
            ],
        ]);
    }
}
