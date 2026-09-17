<?php

declare(strict_types=1);

namespace App\Infrastructure\Directory;

/**
 * Собрано из фрагмента урока 17.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class CachedDirectoryClient
{
    public function findByEmail(string $email): ?Employee
    {
        $key = 'directory:' . hash('xxh128', mb_strtolower($email));
        $cached = $this->cache->get($key, self::MISS);

        if ($cached !== self::MISS) {
            // отрицательный результат закеширован тоже: иначе несуществующий
            // сотрудник запрашивается у чужого сервиса при каждом обращении
            return $cached instanceof Employee ? $cached : null;
        }

        $employee = $this->inner->findByEmail($email);

        // отсутствие кешируем на меньший срок: сотрудник может появиться
        $this->cache->set($key, $employee, $employee === null ? 120 : self::TTL);

        return $employee;
    }
}
