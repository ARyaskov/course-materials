<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\Ticket\Listener;

use App\Application\Survey\Message\SendSurveyMessage;
use App\Application\Ticket\Listener\QueueSatisfactionSurvey;
use App\Domain\Ticket\Event\TicketResolved;
use App\Domain\Ticket\TicketId;
use App\Tests\Support\CollectingQueue;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class QueueSatisfactionSurveyTest extends TestCase
{
    #[Test]
    public function ставит_опрос_для_автора_заявки(): void
    {
        $queue = new CollectingQueue();

        (new QueueSatisfactionSurvey($queue))($this->event(reporterId: 7, actorId: 42));

        $messages = $queue->messagesOfType(SendSurveyMessage::TYPE);

        self::assertCount(1, $messages);
        self::assertSame(7, $messages[0]->getPayload()['recipientId']);
    }

    #[Test]
    public function не_опрашивает_того_кто_сам_закрыл_свою_заявку(): void
    {
        $queue = new CollectingQueue();

        (new QueueSatisfactionSurvey($queue))($this->event(reporterId: 7, actorId: 7));

        self::assertSame([], $queue->messages());
    }

    private function event(int $reporterId, int $actorId): TicketResolved
    {
        return new TicketResolved(
            ticketId: TicketId::fromInt(1042),
            reporterId: $reporterId,
            assigneeId: 42,
            actorId: $actorId,
            occurredAt: new \DateTimeImmutable('2026-09-06 10:00:00'),
        );
    }
}
