<?php
// app/Models/AccessToken.php
declare(strict_types=1);

namespace App\Models;

use Laravel\Sanctum\PersonalAccessToken as SanctumToken;

final class AccessToken extends SanctumToken
{
    protected $table = 'personal_access_tokens';

    protected $fillable = ['name', 'token', 'abilities', 'expires_at', 'ip', 'user_agent'];

    protected function casts(): array
    {
        return [
            'abilities'    => 'json',
            'last_used_at' => 'immutable_datetime',
            'expires_at'   => 'immutable_datetime',
        ];
    }
}
