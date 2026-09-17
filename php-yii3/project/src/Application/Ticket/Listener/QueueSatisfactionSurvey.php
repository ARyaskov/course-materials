<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

use App\Application\Survey\Message\SendSurveyMessage;
use App\Domain\Ticket\Event\TicketResolved;
use Yiisoft\Queue\QueueInterface;

final readonly class QueueSatisfactionSurvey
{
    public function __construct(private QueueInterface $queue)
    {
    }

    public function __invoke(TicketResolved $event): void
    {
        // сотрудник закрыл свою же заявку — опрашивать некого
        if ($event->reporterId === $event->actorId) {
            return;
        }

        // слушатель ставит задачу, а не отправляет письмо сам
        $this->queue->push(new SendSurveyMessage(
            ticketId: $event->ticketId->value,
            recipientId: $event->reporterId,
        ));
    }
}
