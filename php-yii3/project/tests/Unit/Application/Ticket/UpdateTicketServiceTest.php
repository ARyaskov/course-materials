<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\Ticket;

use PHPUnit\Framework\TestCase;

/**
 * Собрано из фрагмента урока 13.6: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class UpdateTicketServiceTest extends TestCase
{
    #[Test]
    public function применяет_только_переданные_поля(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042, title: 'Исходная тема');
        $service = new UpdateTicketService($tickets, new CollectingDispatcher());

        $service->update(new UpdateTicketCommand(
            ticketId: TicketId::fromInt(1042),
            actorId: 7,
            title: null,                       // не прислано — не меняем
            priority: TicketPriority::Critical,
        ));

        $ticket = $tickets->getById(TicketId::fromInt(1042));

        self::assertSame('Исходная тема', $ticket->title);
        self::assertSame(TicketPriority::Critical, $ticket->priority);
    }
}
