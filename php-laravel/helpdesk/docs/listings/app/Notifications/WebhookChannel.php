<?php
// app/Notifications/WebhookChannel.php
declare(strict_types=1);

namespace App\Notifications;

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Http;

final class WebhookChannel extends Channel
{
    public static function name(): string
    {
        return 'webhook';
    }

    protected function deliver(User $user, string $message): void
    {
        Http::timeout(5)
            ->retry(2, 200)
            ->post($user->webhook_url, ['text' => $message])
            ->throw();
    }

    protected function format(Ticket $ticket): string
    {
        return json_encode([
            'ticket_id' => $ticket->id,
            'subject'   => $ticket->subject,
            'status'    => $ticket->status->value,
        ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    }

    protected function supports(User $user): bool
    {
        return $user->webhook_url !== null;
    }
}
