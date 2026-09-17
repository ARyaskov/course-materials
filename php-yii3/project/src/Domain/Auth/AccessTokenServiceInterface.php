<?php

declare(strict_types=1);

namespace App\Domain\Auth;

use App\Domain\User\User;

interface AccessTokenServiceInterface
{
    public function issue(User $user): IssuedToken;

    /** @throws Exception\InvalidTokenException */
    public function validate(string $token): TokenClaims;
}
