<?php

declare(strict_types=1);

namespace App\Infrastructure\Auth;

use App\Domain\Auth\Exception\InvalidTokenException;

final readonly class RotatingJwtService
{
    /** @param array<string, string> $keys идентификатор ключа → значение */
    public function __construct(
        private array $keys,
        private string $currentKeyId,
    ) {
        if (!isset($this->keys[$this->currentKeyId])) {
            throw new \InvalidArgumentException('Текущий ключ отсутствует в наборе.');
        }
    }

    public function sign(array $payload): string
    {
        // идентификатор ключа кладём в заголовок токена
        $header = ['alg' => 'HS256', 'typ' => 'JWT', 'kid' => $this->currentKeyId];

        $head = $this->base64Url(json_encode($header, JSON_THROW_ON_ERROR));
        $body = $this->base64Url(json_encode($payload, JSON_THROW_ON_ERROR));

        return $head . '.' . $body . '.'
            . $this->hmac($head . '.' . $body, $this->keys[$this->currentKeyId]);
    }

    public function verify(string $token): array
    {
        [$head, $body, $signature] = explode('.', $token) + [null, null, null];

        if ($signature === null) {
            throw InvalidTokenException::malformed();
        }

        $header = json_decode($this->base64UrlDecode($head), true, 8, JSON_THROW_ON_ERROR);
        $keyId = $header['kid'] ?? null;

        // ключ выбирается по kid из заголовка, но ТОЛЬКО из известного набора:
        // алгоритм при этом жёстко задан в коде
        if (!is_string($keyId) || !isset($this->keys[$keyId])) {
            throw InvalidTokenException::badSignature();
        }

        if (!hash_equals($this->hmac($head . '.' . $body, $this->keys[$keyId]), $signature)) {
            throw InvalidTokenException::badSignature();
        }

        return json_decode($this->base64UrlDecode($body), true, 8, JSON_THROW_ON_ERROR);
    }

    private function hmac(string $data, string $key): string
    {
        return $this->base64Url(hash_hmac('sha256', $data, $key, true));
    }
}
