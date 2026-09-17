<?php

declare(strict_types=1);

namespace App\Domain\User;

interface UserRepositoryInterface
{
    // ...

    /**
     * Пакетная загрузка — основа борьбы с N+1.
     * @param list<UserId> $ids
     * @return list<User>
     */
    public function findByIds(array $ids): array;
}
