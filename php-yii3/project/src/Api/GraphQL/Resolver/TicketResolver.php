<?php

declare(strict_types=1);

namespace App\Api\GraphQL\Resolver;

use App\Api\Auth\CurrentUser;
use App\Domain\Ticket\TicketFilter;
use App\Application\Ticket\{AssignTicketCommand, AssignTicketService, TicketQueryService};
use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;

/**
 * Другой транспорт — те же сценарии. Слой Api заменяется целиком,
 * Application и Domain остаются нетронутыми.
 */
final readonly class TicketResolver
{
    public function __construct(
        private TicketQueryService $query,
        private AssignTicketService $assign,
        private CurrentUser $currentUser,
    ) {
    }

    /** @param array<string, mixed> $args */
    public function tickets(array $args): array
    {
        // тот же TicketQueryService, что использует REST-обработчик
        return $this->query->paginate(new TicketFilter(
            status: $args['status'] ?? null,
            limit: min((int) ($args['first'] ?? 20), TicketFilter::MAX_LIMIT),
        ))->items;
    }

    /** @param array<string, mixed> $args */
    public function assignTicket(array $args): Ticket
    {
        // тот же сценарий: правила, события и уведомления работают одинаково
        return $this->assign->assign(new AssignTicketCommand(
            ticketId: TicketId::fromInt((int) $args['ticketId']),
            assigneeId: UserId::fromInt((int) $args['assigneeId']),
            actorId: $this->currentUser->id(),
        ));
    }
}
