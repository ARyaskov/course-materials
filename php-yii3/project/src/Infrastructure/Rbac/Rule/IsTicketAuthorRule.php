<?php

declare(strict_types=1);

namespace App\Infrastructure\Rbac\Rule;

use App\Domain\Ticket\{TicketId, TicketRepositoryInterface};
use Yiisoft\Rbac\{Item, RuleContext, RuleInterface};

final readonly class IsTicketAuthorRule implements RuleInterface
{
    // зависимость приходит из контейнера через RulesContainer
    public function __construct(private TicketRepositoryInterface $tickets)
    {
    }

    public function execute(?string $userId, Item $item, RuleContext $context): bool
    {
        if ($userId === null) {
            return false;
        }

        $ticketId = $context->getParameterValue('ticketId');

        if (!is_int($ticketId)) {
            // параметр не передали — правило не может подтвердить доступ
            return false;
        }

        $ticket = $this->tickets->findById(TicketId::fromInt($ticketId));

        return $ticket !== null && $ticket->reporterId === (int) $userId;
    }
}
