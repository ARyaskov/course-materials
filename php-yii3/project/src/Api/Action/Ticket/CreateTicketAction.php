<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Api\Middleware\AuthMiddleware;
use App\Application\Ticket\{CreateTicketCommand, CreateTicketInput, CreateTicketService};
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;
use Yiisoft\Router\UrlGeneratorInterface;

final readonly class CreateTicketAction
{
    public function __construct(
        private CreateTicketService $service,
        private DataResponseFactoryInterface $responseFactory,
        private UrlGeneratorInterface $urlGenerator,
    ) {
    }

    public function __invoke(ServerRequestInterface $request): ResponseInterface
    {
        /** @var CreateTicketInput $input */
        $input = $request->getAttribute(CreateTicketInput::class);

        $ticket = $this->service->create(CreateTicketCommand::fromInput(
            $input,
            // автор берётся из токена, а не из тела запроса
            reporterId: (int) $request->getAttribute(AuthMiddleware::USER_ID),
        ));

        return $this->responseFactory
            ->createResponse(TicketView::fromEntity($ticket), Status::CREATED)
            ->withHeader('Location', $this->urlGenerator->generate(
                'api/v1/tickets/view',
                ['id' => $ticket->id->value],
            ));
    }
}
