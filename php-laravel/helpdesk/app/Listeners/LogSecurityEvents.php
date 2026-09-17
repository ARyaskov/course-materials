<?php
// app/Listeners/LogSecurityEvents.php
declare(strict_types=1);

namespace App\Listeners;

use Illuminate\Auth\Events\Failed;
use Illuminate\Auth\Events\Login;
use Illuminate\Auth\Events\Logout;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Support\Facades\Log;

final class LogSecurityEvents
{
    public function handleLogin(Login $event): void
    {
        Log::channel('security')->info('auth.login', [
            'user_id' => $event->user->getAuthIdentifier(),
            'ip'      => request()->ip(),
            'agent'   => request()->userAgent(),
        ]);
    }

    public function handleFailed(Failed $event): void
    {
        Log::channel('security')->warning('auth.failed', [
            'email' => \App\Support\LogSanitizer::clean(['email' => $event->credentials['email'] ?? null])['email'],
            'ip'    => request()->ip(),
        ]);
    }

    public function handlePasswordReset(PasswordReset $event): void
    {
        Log::channel('security')->notice('auth.password_reset', [
            'user_id' => $event->user->getAuthIdentifier(),
            'ip'      => request()->ip(),
        ]);
    }
}
