<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Ticket;

use App\Domain\Ticket\Exception\IllegalTransitionException;
use App\Domain\Ticket\{Ticket, TicketPriority, TicketStatus};
use App\Domain\User\UserId;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class TicketTest extends TestCase
{
    #[Test]
    public function назначение_переводит_заявку_в_работу(): void
    {
        // ни базы, ни контейнера, ни конфигурации
        $ticket = Ticket::open('Не открывается VPN', 'Ошибка 619.',
            TicketPriority::High, reporterId: 7);

        self::assertSame(TicketStatus::Open, $ticket->status);

        $ticket->assignTo(UserId::fromInt(42), actorId: 7);

        self::assertSame(TicketStatus::InProgress, $ticket->status);
        self::assertSame(42, $ticket->assigneeId?->value);
    }

    #[Test]
    public function повторное_назначение_того_же_исполнителя_ничего_не_меняет(): void
    {
        $ticket = Ticket::open('Заявка', 'Описание заявки.',
            TicketPriority::Normal, reporterId: 7);

        $ticket->assignTo(UserId::fromInt(42), actorId: 7);
        $ticket->releaseEvents();                    // очищаем накопленное

        $ticket->assignTo(UserId::fromInt(42), actorId: 7);

        self::assertSame([], $ticket->releaseEvents(), 'повтор не должен давать событий');
    }

    #[Test]
    public function закрытую_заявку_нельзя_вернуть_в_работу(): void
    {
        $ticket = Ticket::open('Заявка', 'Описание заявки.',
            TicketPriority::Low, reporterId: 7);
        $ticket->changeStatus(TicketStatus::Closed, actorId: 7);

        $this->expectException(IllegalTransitionException::class);

        $ticket->changeStatus(TicketStatus::InProgress, actorId: 7);
    }

    #[Test]
    public function смена_приоритета_пересчитывает_срок_реакции(): void
    {
        $ticket = Ticket::open('Заявка', 'Описание заявки.',
            TicketPriority::Low, reporterId: 7);
        $lowDeadline = $ticket->slaDeadline;

        $ticket->reprioritize(TicketPriority::Critical);

        self::assertLessThan($lowDeadline, $ticket->slaDeadline);
    }

    public function смена_приоритета_пересчитывает_срок(): void
    {
    $ticket = Ticket::open('Заявка', 'Описание заявки.',
        TicketPriority::Low, reporterId: 7);
    $before = $ticket->slaDeadline;

    $ticket->reprioritize(TicketPriority::Critical);

    self::assertLessThan($before, $ticket->slaDeadline);
    }

    /** @return iterable<string, array{TicketStatus, TicketStatus, bool}> */
    public static function transitions(): iterable
    {
    yield 'open → in_progress' => [TicketStatus::Open, TicketStatus::InProgress, true];
    yield 'open → closed' => [TicketStatus::Open, TicketStatus::Closed, true];
    yield 'open → resolved' => [TicketStatus::Open, TicketStatus::Resolved, false];
    yield 'in_progress → resolved' => [TicketStatus::InProgress, TicketStatus::Resolved, true];
    yield 'closed → in_progress' => [TicketStatus::Closed, TicketStatus::InProgress, false];
    yield 'closed → open' => [TicketStatus::Closed, TicketStatus::Open, false];
    }

    #[Test]
    #[DataProvider('transitions')]
    public function матрица_переходов_статуса(
    TicketStatus $from,
    TicketStatus $to,
    bool $allowed,
    ): void {
    $ticket = $this->ticketInStatus($from);

    if (!$allowed) {
        $this->expectException(IllegalTransitionException::class);
    }

    $ticket->changeStatus($to, actorId: 7);

    if ($allowed) {
        self::assertSame($to, $ticket->status);
    }
    }

    #[Test]
    public function сообщение_об_ошибке_перечисляет_допустимые_переходы(): void
    {
    $ticket = $this->ticketInStatus(TicketStatus::Open);

    try {
        $ticket->changeStatus(TicketStatus::Resolved, actorId: 7);
        self::fail('ожидалось исключение');
    } catch (IllegalTransitionException $e) {
        // клиент должен понять, что делать дальше, из самого сообщения
        self::assertStringContainsString('in_progress', $e->getMessage());
        self::assertStringContainsString('closed', $e->getMessage());
    }
    }
}
