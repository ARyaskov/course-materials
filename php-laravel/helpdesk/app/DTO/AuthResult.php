<?php
// app/DTO/AuthResult.php
declare(strict_types=1);

namespace App\DTO;

use App\Models\User;

final readonly class AuthResult
{
    public function __construct(
        public User $user,
        public string $token,
    ) {
    }
}
