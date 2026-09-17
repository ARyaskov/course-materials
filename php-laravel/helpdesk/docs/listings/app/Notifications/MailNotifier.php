<?php
// app/Notifications/MailNotifier.php
declare(strict_types=1);

namespace App\Notifications;

use App\Contracts\Notifier;
use App\Models\User;
use Illuminate\Support\Facades\Mail;

final readonly class MailNotifier implements Notifier
{
    public function send(User $recipient, string $message): void
    {
        Mail::raw($message, fn ($mail) => $mail->to($recipient->email)->subject('HelpDesk'));
    }

    public function supports(User $recipient): bool
    {
        return $recipient->email !== null && $recipient->email_verified_at !== null;
    }
}
