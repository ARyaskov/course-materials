<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\Ticket;

use App\Application\Ticket\{AssignTicketCommand, AssignTicketService};
use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Domain\Ticket\Exception\{AssigneeOverloadedException, TicketNotFoundException};
use App\Domain\Ticket\{TicketId, TicketStatus};
use App\Domain\User\UserId;
use App\Tests\Support\{CollectingQueue, InMemoryTicketRepository, InMemoryUserRepository};
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class AssignTicketServiceTest extends TestCase
{
    #[Test]
    public function назначает_исполнителя_и_ставит_уведомление(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042);
        $queue = new CollectingQueue();

        $ticket = $this->service($tickets, $queue)->assign($this->command());

        // проверяем НАБЛЮДАЕМЫЙ результат, а не последовательность вызовов
        self::assertSame(42, $ticket->assigneeId?->value);
        self::assertSame(TicketStatus::InProgress, $ticket->status);
        self::assertCount(1, $queue->messagesOfType(NotifyAssigneeMessage::TYPE));
    }

    #[Test]
    public function повторное_назначение_не_шлёт_второго_уведомления(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042);
        $queue = new CollectingQueue();
        $service = $this->service($tickets, $queue);

        $service->assign($this->command());
        $service->assign($this->command());

        self::assertCount(1, $queue->messagesOfType(NotifyAssigneeMessage::TYPE));
    }

    #[Test]
    public function отказывает_при_перегрузке_исполнителя(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042)
            ->withOpenCountForAssignee(42, 10);

        $this->expectException(AssigneeOverloadedException::class);

        $this->service($tickets, new CollectingQueue())->assign($this->command());
    }

    #[Test]
    public function несуществующая_заявка_даёт_исключение(): void
    {
        $this->expectException(TicketNotFoundException::class);

        $this->service(new InMemoryTicketRepository(), new CollectingQueue())
            ->assign(new AssignTicketCommand(
                ticketId: TicketId::fromInt(999),
                assigneeId: UserId::fromInt(42),
                actorId: UserId::fromInt(7),
            ));
    }

    #[Test]
    public function при_отказе_уведомление_не_ставится(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042)
            ->withOpenCountForAssignee(42, 10);
        $queue = new CollectingQueue();

        try {
            $this->service($tickets, $queue)->assign($this->command());
        } catch (AssigneeOverloadedException) {
            // побочный эффект не должен произойти при неуспешном сценарии
            self::assertSame([], $queue->messages());
        }
    }

    private function command(): AssignTicketCommand
    {
        return new AssignTicketCommand(
            ticketId: TicketId::fromInt(1042),
            assigneeId: UserId::fromInt(42),
            actorId: UserId::fromInt(7),
        );
    }

    private function service(
        InMemoryTicketRepository $tickets,
        CollectingQueue $queue,
    ): AssignTicketService {
        return new AssignTicketService(
            $tickets,
            InMemoryUserRepository::withUser(id: 42, email: 'ops@helpdesk.example'),
            $queue,
            maxOpenPerAssignee: 10,
        );
    }

    public function назначает_ответственного_и_ставит_уведомление(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042);
        $users = InMemoryUserRepository::withUser(id: 42, email: 'ops@helpdesk.example');
        $queue = new CollectingQueue();

        // ни контейнера, ни конфигурации, ни базы — четыре объекта и вызов
        $service = new AssignTicketService($tickets, $users, $queue, new NullLogger());

        $ticket = $service->assign(TicketId::fromInt(1042), UserId::fromInt(42));

        self::assertSame(42, $ticket->assigneeId);
        self::assertCount(1, $queue->messagesOfType(NotifyAssigneeMessage::TYPE));
    }

    #[Test]
    public function бросает_исключение_для_несуществующей_заявки(): void
    {
        $service = new AssignTicketService(
            new InMemoryTicketRepository(withSeedData: false),
            InMemoryUserRepository::withUser(id: 42, email: 'ops@helpdesk.example'),
            new CollectingQueue(),
            new NullLogger(),
        );

        $this->expectException(TicketNotFoundException::class);

        $service->assign(TicketId::fromInt(999), UserId::fromInt(42));
    }

    public function назначает_и_переводит_в_работу(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042);
        $queue = new CollectingQueue();

        $ticket = $this->service($tickets, $queue)->assign($this->command());

        self::assertSame(42, $ticket->assigneeId?->value);
        self::assertSame(TicketStatus::InProgress, $ticket->status);
        self::assertCount(1, $queue->messagesOfType(NotifyAssigneeMessage::TYPE));
    }

    #[Test]
    public function отказывает_при_перегрузке_сотрудника(): void
    {
        $tickets = InMemoryTicketRepository::withTicket(id: 1042)
            ->withOpenCountForAssignee(42, 10);

        $this->expectException(AssigneeOverloadedException::class);

        $this->service($tickets, new CollectingQueue())->assign($this->command());
    }
}
