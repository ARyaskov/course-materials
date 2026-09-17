<?php
// app/Notifications/MailChannel.php
declare(strict_types=1);

namespace App\Notifications;

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Mail;

final class MailChannel extends Channel
{
    public static function name(): string
    {
        return 'mail';
    }

    protected function deliver(User $user, string $message): void
    {
        Mail::raw($message, fn ($mail) => $mail->to($user->email)->subject('HelpDesk'));
    }

    protected function supports(User $user): bool
    {
        return $user->email !== null && $user->email_verified_at !== null;
    }
}
