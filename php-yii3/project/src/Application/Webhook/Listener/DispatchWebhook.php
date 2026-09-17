<?php

declare(strict_types=1);

namespace App\Application\Webhook\Listener;

use App\Application\Webhook\Message\SendWebhookMessage;
use App\Domain\Ticket\Event\{TicketAssigned, TicketOpened, TicketStatusChanged};
use App\Domain\Webhook\WebhookSubscriptionRepositoryInterface;
use Yiisoft\Queue\QueueInterface;

/**
 * Вебхуки — обычный слушатель доменных событий. Сценарии
 * о них не знают, потому что событие не знает своих слушателей.
 */
final readonly class DispatchWebhook
{
    public function __construct(
        private WebhookSubscriptionRepositoryInterface $subscriptions,
        private QueueInterface $queue,
    ) {
    }

    public function onOpened(TicketOpened $event): void
    {
        $this->dispatch('ticket.opened', [
            'ticketId' => $event->ticketId->value,
            'priority' => $event->priority->value,
            'occurredAt' => $event->occurredAt->format(\DateTimeInterface::ATOM),
        ]);
    }

    public function onStatusChanged(TicketStatusChanged $event): void
    {
        $this->dispatch('ticket.status_changed', [
            'ticketId' => $event->ticketId->value,
            'from' => $event->from->value,
            'to' => $event->to->value,
        ]);
    }

    /** @param array<string, mixed> $payload */
    private function dispatch(string $eventType, array $payload): void
    {
        foreach ($this->subscriptions->findActiveFor($eventType) as $subscription) {
            // отправка — в очередь: недоступность получателя
            // не должна влиять на время ответа HelpDesk
            $this->queue->push(new SendWebhookMessage(
                subscriptionId: $subscription->id,
                eventType: $eventType,
                payload: $payload,
                // ключ идемпотентности: повтор не создаст у получателя дубля
                eventId: bin2hex(random_bytes(16)),
            ));
        }
    }
}
