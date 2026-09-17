<?php

declare(strict_types=1);

namespace App\Application\Auth;

use App\Domain\Auth\Exception\InvalidTokenException;
use App\Domain\Auth\{AccessTokenServiceInterface, RefreshTokenRepositoryInterface, TokenPair};
use App\Domain\User\UserRepositoryInterface;
use Psr\Log\LoggerInterface;

final readonly class RefreshTokenService
{
    private const TTL_DAYS = 30;

    public function __construct(
        private RefreshTokenRepositoryInterface $tokens,
        private UserRepositoryInterface $users,
        private AccessTokenServiceInterface $accessTokens,
        private LoggerInterface $logger,
    ) {
    }

    public function refresh(string $refreshToken): TokenPair
    {
        // в базе лежит хеш — ищем по нему
        $hash = hash('sha256', $refreshToken);
        $stored = $this->tokens->findByHash($hash) ?? throw InvalidTokenException::unknown();

        if ($stored->isRevoked()) {
            // токен уже использовали: либо его украли, либо это повтор.
            // Отзываем всю цепочку — так атака становится заметной.
            $this->tokens->revokeAllForUser($stored->userId);

            $this->logger->warning('Повторное использование refresh-токена', [
                'userId' => $stored->userId->value,
            ]);

            throw InvalidTokenException::reused();
        }

        if ($stored->isExpired(new \DateTimeImmutable())) {
            throw InvalidTokenException::expired();
        }

        $user = $this->users->getById($stored->userId);

        // ротация: старый токен становится недействительным немедленно
        $newRefresh = bin2hex(random_bytes(32));
        $this->tokens->rotate($stored, hash('sha256', $newRefresh), self::TTL_DAYS);

        return new TokenPair(
            accessToken: $this->accessTokens->issue($user),
            refreshToken: $newRefresh,
        );
    }
}
