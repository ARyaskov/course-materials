<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\Ticket\TicketId;
use App\Domain\Ticket\TicketRepositoryInterface;
use Psr\Http\Message\ResponseInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Router\CurrentRoute;

final readonly class ViewTicketAction
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(CurrentRoute $route): ResponseInterface
    {
        $id = TicketId::fromInt((int) $route->getArgument('id'));

        // карточка со связями: два запроса, не N+1
        $model = $this->tickets->findWithComments($id)
            ?? throw TicketNotFoundException::withId($id);

        return $this->responseFactory->createResponse(
            TicketDetailView::fromReadModel($model),
        );
    }
}
