<?php
// app/Services/Notifications/CircuitBreakerNotifier.php
declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Models\User;
use Illuminate\Support\Facades\Cache;

final readonly class CircuitBreakerNotifier implements Notifier
{
    private const int THRESHOLD = 5;
    private const int COOLDOWN = 60;

    public function __construct(private Notifier $inner)
    {
    }

    public function send(User $recipient, string $subject, string $body): void
    {
        $key = "circuit:{$this->inner->channel()}";

        if ((int) Cache::get($key, 0) >= self::THRESHOLD) {
            throw new \App\Exceptions\ExternalServiceUnavailableException($this->inner->channel());
        }

        try {
            $this->inner->send($recipient, $subject, $body);
            Cache::forget($key);
        } catch (\Throwable $e) {
            Cache::put($key, (int) Cache::get($key, 0) + 1, self::COOLDOWN);

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
