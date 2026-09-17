<?php
// app/Services/Notifications/QueueNotifier.php
declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Jobs\SendNotification;
use App\Models\User;

final readonly class QueueNotifier implements Notifier
{
    public function __construct(private Notifier $inner)
    {
    }

    public function send(User $recipient, string $subject, string $body): void
    {
        SendNotification::dispatch($this->inner->channel(), $recipient->id, $subject, $body)
            ->afterCommit();
    }

    public function supports(User $recipient): bool
    {
        return $this->inner->supports($recipient);
    }

    public function channel(): string
    {
        return $this->inner->channel();
    }
}
