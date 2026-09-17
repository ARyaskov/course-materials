<?php
// app/Notifications/QueueNotifier.php — оборачивает другой Notifier
declare(strict_types=1);

namespace App\Notifications;

use App\Contracts\Notifier;
use App\Jobs\SendNotification;
use App\Models\User;

final readonly class QueueNotifier implements Notifier
{
    public function __construct(private Notifier $inner)
    {
    }

    public function send(User $recipient, string $message): void
    {
        SendNotification::dispatch($recipient->id, $message)->afterCommit();
    }

    public function supports(User $recipient): bool
    {
        return $this->inner->supports($recipient);
    }
}
