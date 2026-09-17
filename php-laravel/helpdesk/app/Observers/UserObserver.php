<?php

declare(strict_types=1);

namespace App\Observers;

use App\Models\User;
use Illuminate\Support\Facades\Cache;

final class UserObserver
{
    public function updated(User $user): void
    {
        if ($user->wasChanged('role')) {
            Cache::forget("permissions:user:{$user->id}");
            Cache::increment('permissions:generation');

            // и токены отозвать
            $user->tokens()->delete();
        }
    }
}
