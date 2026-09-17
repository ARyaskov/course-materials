<?php
// app/Services/Notifications/WebhookNotifier.php
declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Exceptions\ExternalServiceUnavailableException;
use App\Models\User;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

final readonly class WebhookNotifier implements Notifier
{
    public function __construct(private int $timeout = 5)
    {
    }

    public function send(User $recipient, string $subject, string $body): void
    {
        try {
            Http::timeout($this->timeout)
                ->retry(2, 200)
                ->post($recipient->webhook_url, ['subject' => $subject, 'text' => $body])
                ->throw();
        } catch (ConnectionException $e) {
            throw new ExternalServiceUnavailableException('webhook', previous: $e);
        }
    }

    public function supports(User $recipient): bool
    {
        return $recipient->webhook_url !== null;
    }

    public function channel(): string
    {
        return 'webhook';
    }
}
