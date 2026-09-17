<?php

declare(strict_types=1);

namespace App\Infrastructure\Auth;

use App\Domain\Auth\Exception\{InvalidTokenException, TokenExpiredException};
use App\Domain\Auth\{AccessTokenServiceInterface, IssuedToken, TokenClaims};
use App\Domain\User\{User, UserRole};

final readonly class JwtAccessTokenService implements AccessTokenServiceInterface
{
    public function __construct(
        private string $secret,
        private int $ttlSeconds = 900,
        private string $issuer = 'helpdesk',
    ) {
        if (strlen($secret) < 32) {
            throw new \InvalidArgumentException('Ключ подписи короче 32 байт.');
        }
    }

    public function issue(User $user): IssuedToken
    {
        $now = new \DateTimeImmutable();
        $expiresAt = $now->modify("+{$this->ttlSeconds} seconds");

        $payload = [
            'iss' => $this->issuer,
            'sub' => (string) $user->id->value,
            'email' => $user->email,
            'role' => $user->role->value,
            'permissions' => $user->role->permissions(),
            'iat' => $now->getTimestamp(),
            'exp' => $expiresAt->getTimestamp(),
            'jti' => bin2hex(random_bytes(8)),
        ];

        return new IssuedToken($this->encode($payload), $expiresAt);
    }

    public function validate(string $token): TokenClaims
    {
        $parts = explode('.', $token);

        if (count($parts) !== 3) {
            throw InvalidTokenException::malformed();
        }

        [$header64, $payload64, $signature64] = $parts;

        $expected = $this->sign($header64 . '.' . $payload64);

        // сравнение за постоянное время: иначе подпись подбирается побайтово
        if (!hash_equals($expected, $signature64)) {
            throw InvalidTokenException::badSignature();
        }

        $payload = json_decode($this->base64UrlDecode($payload64), true, 8, JSON_THROW_ON_ERROR);

        if (($payload['iss'] ?? null) !== $this->issuer) {
            throw InvalidTokenException::badIssuer();
        }

        $expiresAt = new \DateTimeImmutable('@' . (int) ($payload['exp'] ?? 0));

        // отдельное исключение: клиент должен понять, что нужен refresh
        if ($expiresAt < new \DateTimeImmutable()) {
            throw TokenExpiredException::at($expiresAt);
        }

        return new TokenClaims(
            userId: (int) $payload['sub'],
            email: (string) $payload['email'],
            role: UserRole::from((string) $payload['role']),
            permissions: (array) ($payload['permissions'] ?? []),
            issuedAt: new \DateTimeImmutable('@' . (int) $payload['iat']),
            expiresAt: $expiresAt,
            tokenId: (string) $payload['jti'],
        );
    }

    private function encode(array $payload): string
    {
        $header = $this->base64UrlEncode(json_encode(
            ['alg' => 'HS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR,
        ));

        $body = $this->base64UrlEncode(json_encode($payload, JSON_THROW_ON_ERROR));

        return $header . '.' . $body . '.' . $this->sign($header . '.' . $body);
    }

    private function sign(string $data): string
    {
        return $this->base64UrlEncode(hash_hmac('sha256', $data, $this->secret, true));
    }

    private function base64UrlEncode(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    private function base64UrlDecode(string $encoded): string
    {
        return base64_decode(strtr($encoded, '-_', '+/'), true)
            ?: throw InvalidTokenException::malformed();
    }
}
