<?php
// app/Services/Notifications/MailNotifier.php
declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Models\User;
use Illuminate\Support\Facades\Mail;

final readonly class MailNotifier implements Notifier
{
    public function send(User $recipient, string $subject, string $body): void
    {
        Mail::raw($body, fn ($mail) => $mail->to($recipient->email)->subject($subject));
    }

    public function supports(User $recipient): bool
    {
        return $recipient->email !== null && $recipient->email_verified_at !== null;
    }

    public function channel(): string
    {
        return 'mail';
    }
}
