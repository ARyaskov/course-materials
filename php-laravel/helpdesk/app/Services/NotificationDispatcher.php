<?php
// app/Services/NotificationDispatcher.php
declare(strict_types=1);

namespace App\Services;

use App\Contracts\Notifier;
use App\Models\Ticket;
use App\Models\User;

final readonly class NotificationDispatcher
{
    /** @param  iterable<Notifier>  $notifiers */
    public function __construct(private iterable $notifiers)
    {
    }

    public function notify(User $user, Ticket $ticket, string $message): int
    {
        $sent = 0;

        foreach ($this->notifiers as $notifier) {
            if (! $notifier->supports($user)) {
                continue;
            }

            rescue(function () use ($notifier, $user, $message, &$sent): void {
                $notifier->send($user, $message);
                $sent++;
            });
        }

        return $sent;
    }
}
