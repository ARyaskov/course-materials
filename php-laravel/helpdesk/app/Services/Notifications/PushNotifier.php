<?php

declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Models\User;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

final readonly class PushNotifier implements Notifier
{
    public function __construct(
        private ?string $endpoint = null,
        private int $timeout = 5,
    ) {
    }

    public function send(User $recipient, string $subject, string $body): void
    {
        $endpoint = $this->endpoint ?? config('services.push.url');

        if ($endpoint === null) {
            Log::warning('push.endpoint_missing', ['user_id' => $recipient->id]);

            return;
        }

        Http::timeout($this->timeout)
            ->retry(2, 200, throw: false)
            ->post($endpoint, [
                'token' => $recipient->push_token,
                'title' => $subject,
                'body' => $body,
            ]);
    }

    public function supports(User $recipient): bool
    {
        return ! empty($recipient->push_token);
    }

    public function channel(): string
    {
        return 'push';
    }
}
