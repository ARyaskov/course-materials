<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Application\Ticket\ChangeTicketStatusService;
use App\Application\Ticket\ChangeStatusInput;
use App\Domain\Ticket\Exception\IllegalTransitionException;
use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\Ticket\TicketId;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;
use Yiisoft\Router\CurrentRoute;

final readonly class ChangeStatusAction
{
    public function __construct(
        private ChangeTicketStatusService $service,
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(
        ServerRequestInterface $request,
        CurrentRoute $currentRoute,
    ): ResponseInterface {
        // 1. достать данные из HTTP-мира
        $input = $request->getAttribute(ChangeStatusInput::class);
        $ticketId = TicketId::fromInt((int) $currentRoute->getArgument('id'));
        $actorId = $request->getAttribute('userId');

        // 2. вызвать сценарий — одна строка, никаких условий
        try {
            $ticket = $this->service->changeStatus($ticketId, $input->status, $actorId);
        } catch (TicketNotFoundException $e) {
            return $this->error('not_found', $e->getMessage(), Status::NOT_FOUND);
        } catch (IllegalTransitionException $e) {
            // доменное правило нарушено — это 409, а не 500 и не 422
            return $this->error('illegal_transition', $e->getMessage(), Status::CONFLICT);
        }

        // 3. превратить результат в HTTP-ответ
        return $this->responseFactory->createResponse(TicketView::fromEntity($ticket));
    }

    private function error(string $type, string $message, int $status): ResponseInterface
    {
        return $this->responseFactory->createResponse(
            ['error' => ['type' => $type, 'message' => $message]],
            $status,
        );
    }
}
