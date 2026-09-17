<?php
// app/Notifications/Channel.php
declare(strict_types=1);

namespace App\Notifications;

use App\Models\Ticket;
use App\Models\User;
use Psr\Log\LoggerInterface;

abstract class Channel
{
    public function __construct(protected readonly LoggerInterface $logger)
    {
    }

    /** Шаблонный метод: общий порядок для всех каналов. */
    final public function notify(User $user, Ticket $ticket): bool
    {
        if (! $this->supports($user)) {
            return false;
        }

        $message = $this->format($ticket);

        try {
            $this->deliver($user, $message);
            $this->logger->info('notification.sent', [
                'channel' => static::name(),
                'user'    => $user->id,
                'ticket'  => $ticket->id,
            ]);

            return true;
        } catch (\Throwable $e) {
            $this->logger->warning('notification.failed', [
                'channel' => static::name(),
                'error'   => $e->getMessage(),
            ]);

            return false;
        }
    }

    abstract public static function name(): string;

    abstract protected function deliver(User $user, string $message): void;

    /** Наследник может переопределить, но не обязан. */
    protected function format(Ticket $ticket): string
    {
        return "Заявка #{$ticket->id}: {$ticket->subject} — {$ticket->status->label()}";
    }

    protected function supports(User $user): bool
    {
        return true;
    }
}
