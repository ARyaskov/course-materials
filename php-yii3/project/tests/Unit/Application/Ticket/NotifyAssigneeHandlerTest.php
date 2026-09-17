<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\Ticket;

use App\Application\Ticket\Message\NotifyAssigneeHandler;
use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Tests\Support\FakeMailer;
use App\Tests\Support\InMemoryTicketRepository;
use App\Tests\Support\InMemoryUserRepository;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;

final class NotifyAssigneeHandlerTest extends TestCase
{
    #[Test]
    public function отправляет_письмо_ответственному(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042, assigneeId: 42);
        $users = InMemoryUserRepository::withUser(id: 42, email: 'ops@helpdesk.example');
        $mailer = new FakeMailer();

        $handler = new NotifyAssigneeHandler($tickets, $users, $mailer, new NullLogger());
        $handler->handle(new NotifyAssigneeMessage(ticketId: 1042, assigneeId: 42));

        self::assertSame(1, $mailer->sentCount());
        self::assertSame('ops@helpdesk.example', $mailer->sent()[0]['assignee']->email);
    }

    #[Test]
    public function молча_пропускает_удалённую_заявку(): void
    {
        $handler = new NotifyAssigneeHandler(
            new InMemoryTicketRepository(),          // заявки нет
            InMemoryUserRepository::withUser(id: 42, email: 'ops@helpdesk.example'),
            $mailer = new FakeMailer(),
            new NullLogger(),
        );

        // не должно быть исключения: сообщение не должно уйти в бесконечные повторы
        $handler->handle(new NotifyAssigneeMessage(ticketId: 999, assigneeId: 42));

        self::assertSame(0, $mailer->sentCount());
    }

    #[Test]
    public function повторная_обработка_не_отправляет_второго_письма(): void
    {
    $mailer = new FakeMailer();
    $handler = $this->handler($mailer);
    $message = new NotifyAssigneeMessage(ticketId: 1042, assigneeId: 42);

    $handler->handle($message);
    $handler->handle($message);          // та же доставка ещё раз

    self::assertSame(1, $mailer->sentCount());
    }
}
