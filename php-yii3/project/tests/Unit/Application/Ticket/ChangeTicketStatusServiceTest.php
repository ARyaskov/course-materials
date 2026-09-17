<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\Ticket;

use App\Application\Ticket\ChangeTicketStatusService;
use App\Domain\Ticket\Event\{TicketResolved, TicketStatusChanged};
use App\Domain\Ticket\{TicketId, TicketStatus};
use App\Tests\Support\{CollectingDispatcher, InMemoryTicketRepository};
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class ChangeTicketStatusServiceTest extends TestCase
{
    #[Test]
    public function публикует_два_события_при_решении_заявки(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(
            id: 1042, status: TicketStatus::InProgress, assigneeId: 42,
        );
        $events = new CollectingDispatcher();

        (new ChangeTicketStatusService($tickets, $events))
            ->changeStatus(TicketId::fromInt(1042), TicketStatus::Resolved, actorId: 42);

        self::assertCount(1, $events->of(TicketStatusChanged::class));
        self::assertCount(1, $events->of(TicketResolved::class));
    }

    #[Test]
    public function не_публикует_resolved_при_обычном_переходе(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042, status: TicketStatus::Open);
        $events = new CollectingDispatcher();

        (new ChangeTicketStatusService($tickets, $events))
            ->changeStatus(TicketId::fromInt(1042), TicketStatus::InProgress, actorId: 42);

        self::assertCount(1, $events->of(TicketStatusChanged::class));
        self::assertSame([], $events->of(TicketResolved::class));
    }

    #[Test]
    public function не_публикует_событий_при_недопустимом_переходе(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042, status: TicketStatus::Closed);
        $events = new CollectingDispatcher();

        try {
            (new ChangeTicketStatusService($tickets, $events))
                ->changeStatus(TicketId::fromInt(1042), TicketStatus::Resolved, actorId: 42);
            self::fail('ожидалось исключение');
        } catch (\DomainException) {
            self::assertSame([], $events->all());
        }
    }
}
