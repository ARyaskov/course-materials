<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\Ticket;

use App\Application\Ticket\CreateTicketInput;
use App\Application\Ticket\CreateTicketService;
use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Domain\Ticket\TicketPriority;
use App\Tests\Support\CollectingQueue;
use App\Tests\Support\InMemoryTicketRepository;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class CreateTicketServiceTest extends TestCase
{
    #[Test]
    public function ставит_уведомление_в_очередь_когда_есть_ответственный(): void
    {
        $queue = new CollectingQueue();
        $service = new CreateTicketService(new InMemoryTicketRepository(), $queue);

        $ticket = $service->create(new CreateTicketInput(
            title: 'Не открывается VPN',
            description: 'С утра ошибка 619',
            priority: TicketPriority::High,
            reporterId: 7,
            assigneeId: 42,
        ));

        $messages = $queue->messagesOfType(NotifyAssigneeMessage::TYPE);

        self::assertCount(1, $messages);
        self::assertSame(
            ['ticketId' => $ticket->id->value, 'assigneeId' => 42],
            $messages[0]->getPayload(),
        );
    }

    #[Test]
    public function не_ставит_уведомление_когда_ответственный_не_назначен(): void
    {
        $queue = new CollectingQueue();
        $service = new CreateTicketService(new InMemoryTicketRepository(), $queue);

        $service->create(new CreateTicketInput(
            title: 'Заявка без ответственного',
            description: '...',
            priority: TicketPriority::Normal,
            reporterId: 7,
            assigneeId: null,
        ));

        self::assertSame([], $queue->messages());
    }
}
