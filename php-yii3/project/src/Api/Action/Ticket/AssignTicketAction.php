<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Api\Middleware\AuthMiddleware;
use App\Application\Ticket\{AssignTicketCommand, AssignTicketInput, AssignTicketService};
use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Router\CurrentRoute;

final readonly class AssignTicketAction
{
    public function __construct(
        private AssignTicketService $service,
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(
        ServerRequestInterface $request,
        CurrentRoute $currentRoute,
    ): ResponseInterface {
        /** @var AssignTicketInput $input */
        $input = $request->getAttribute(AssignTicketInput::class);

        $ticket = $this->service->assign(new AssignTicketCommand(
            ticketId: TicketId::fromInt((int) $currentRoute->getArgument('id')),
            assigneeId: UserId::fromInt((int) $input->assigneeId),
            actorId: UserId::fromInt($request->getAttribute(AuthMiddleware::USER_ID)),
            comment: $input->comment,
        ));

        return $this->responseFactory->createResponse(TicketView::fromEntity($ticket));
    }
}
