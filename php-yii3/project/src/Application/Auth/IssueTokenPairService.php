<?php

declare(strict_types=1);

namespace App\Application\Auth;

use App\Domain\Auth\{AccessTokenServiceInterface, RefreshTokenRepositoryInterface, TokenPair};
use App\Domain\User\User;

final readonly class IssueTokenPairService
{
    private const REFRESH_TTL_DAYS = 30;

    public function __construct(
        private AccessTokenServiceInterface $accessTokens,
        private RefreshTokenRepositoryInterface $refreshTokens,
    ) {
    }

    public function issueFor(User $user, string $userAgent = ''): TokenPair
    {
        // непрозрачная случайная строка: в базе хранится её хеш
        $refresh = bin2hex(random_bytes(32));

        $this->refreshTokens->store(
            userId: $user->id,
            tokenHash: hash('sha256', $refresh),
            expiresAt: (new \DateTimeImmutable())->modify('+' . self::REFRESH_TTL_DAYS . ' days'),
            userAgent: mb_substr($userAgent, 0, 255),
        );

        return new TokenPair(
            // короткоживущий JWT: 15 минут, проверяется локально
            accessToken: $this->accessTokens->issue($user),
            refreshToken: $refresh,
        );
    }
}
