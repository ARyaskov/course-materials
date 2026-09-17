<?php
// app/Services/Notifications/LoggingNotifier.php
declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Models\User;
use Psr\Log\LoggerInterface;

final readonly class LoggingNotifier implements Notifier
{
    public function __construct(
        private Notifier $inner,
        private LoggerInterface $logger,
    ) {
    }

    public function send(User $recipient, string $subject, string $body): void
    {
        $start = hrtime(true);

        try {
            $this->inner->send($recipient, $subject, $body);

            $this->logger->info('notification.sent', [
                'channel' => $this->inner->channel(),
                'user_id' => $recipient->id,
                'ms'      => round((hrtime(true) - $start) / 1_000_000, 1),
            ]);
        } catch (\Throwable $e) {
            $this->logger->warning('notification.failed', [
                'channel'   => $this->inner->channel(),
                'user_id'   => $recipient->id,
                'exception' => $e::class,
            ]);

            throw $e;
        }
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
