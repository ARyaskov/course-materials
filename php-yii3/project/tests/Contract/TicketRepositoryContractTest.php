<?php

declare(strict_types=1);

namespace App\Tests\Contract;

use App\Domain\Ticket\{Ticket, TicketFilter, TicketId,
                       TicketPriority, TicketRepositoryInterface, TicketStatus};
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/** Один набор проверок, который обязаны пройти ВСЕ реализации. */
abstract class TicketRepositoryContractTest extends TestCase
{
    abstract protected function createRepository(): TicketRepositoryInterface;

    #[Test]
    public function присваивает_идентификатор_при_первом_сохранении(): void
    {
        $repository = $this->createRepository();
        $ticket = Ticket::open('Не открывается VPN', 'Ошибка 619.',
            TicketPriority::High, reporterId: 7);

        self::assertTrue($ticket->id->isNew());

        $repository->save($ticket);

        self::assertFalse($ticket->id->isNew());
        self::assertNotNull($repository->findById($ticket->id));
    }

    #[Test]
    public function фильтрует_по_статусу(): void
    {
        $repository = $this->createRepository();

        $open = Ticket::open('Открытая', 'Описание заявки.',
            TicketPriority::Normal, reporterId: 7);
        $repository->save($open);

        $closed = Ticket::open('Закрытая', 'Описание заявки.',
            TicketPriority::Low, reporterId: 7);
        $closed->changeStatus(TicketStatus::Closed, actorId: 7);
        $repository->save($closed);

        $result = $repository->findByFilter(new TicketFilter(status: 'open'));

        self::assertCount(1, $result);
        self::assertSame('Открытая', $result[0]->title);
    }

    #[Test]
    public function возвращает_null_для_несуществующей_заявки(): void
    {
        self::assertNull($this->createRepository()->findById(TicketId::fromInt(999999)));
    }
}
