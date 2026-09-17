<?php

declare(strict_types=1);

namespace App\Domain\User;

interface PasswordHasherInterface
{
    public function hash(string $plainPassword): string;

    public function verify(string $plainPassword, string $hash): bool;

    /** Нужно ли пересчитать хеш: параметры алгоритма изменились. */
    public function needsRehash(string $hash): bool;
}
