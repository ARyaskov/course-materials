<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Api\Auth\CurrentUser;
use App\Domain\Ticket\{TicketId, TicketRepositoryInterface};

final readonly class ViewTicketService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private TicketPolicy $policy,
        private CurrentUser $currentUser,
    ) {
    }

    public function view(TicketId $id): TicketWithComments
    {
        // сначала загружаем — проверить принадлежность без объекта нельзя
        $model = $this->tickets->findWithComments($id)
            ?? throw TicketNotFoundException::withId($id);

        $this->policy->assertCanView(
            $model->ticket,
            $this->currentUser->id(),
            $this->currentUser->role(),
        );

        return $model;
    }
}
