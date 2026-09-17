<?php

declare(strict_types=1);

namespace App\Infrastructure\User;

use App\Domain\User\PasswordHasherInterface;

final readonly class Argon2PasswordHasher implements PasswordHasherInterface
{
    /** @param array{memory_cost?: int, time_cost?: int, threads?: int} $options */
    public function __construct(private array $options = [
        'memory_cost' => 65536,   // 64 МБ на вычисление
        'time_cost' => 4,
        'threads' => 2,
    ]) {
    }

    public function hash(string $plainPassword): string
    {
        // соль генерируется автоматически и хранится внутри строки хеша
        $hash = password_hash($plainPassword, PASSWORD_ARGON2ID, $this->options);

        if ($hash === false) {
            throw new \RuntimeException('Не удалось вычислить хеш пароля.');
        }

        return $hash;
    }

    public function verify(string $plainPassword, string $hash): bool
    {
        // сравнение за постоянное время: защита от атаки по времени
        return password_verify($plainPassword, $hash);
    }

    public function needsRehash(string $hash): bool
    {
        return password_needs_rehash($hash, PASSWORD_ARGON2ID, $this->options);
    }
}
