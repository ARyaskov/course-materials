<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Api\Middleware\AuthMiddleware;
use App\Application\Ticket\DeleteTicketService;
use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Psr\Http\Message\ResponseFactoryInterface;
use Yiisoft\Http\Status;
use Yiisoft\Router\CurrentRoute;

final readonly class DeleteTicketAction
{
    public function __construct(
        private DeleteTicketService $service,
        private ResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(
        ServerRequestInterface $request,
        CurrentRoute $route,
    ): ResponseInterface {
        $this->service->delete(
            TicketId::fromInt((int) $route->getArgument('id')),
            UserId::fromInt((int) $request->getAttribute(AuthMiddleware::USER_ID)),
        );

        // 204: тела нет, поэтому обычная фабрика ответов, а не DataResponse
        return $this->responseFactory->createResponse(Status::NO_CONTENT);
    }
}
