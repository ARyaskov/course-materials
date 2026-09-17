<?php

declare(strict_types=1);

namespace App\Infrastructure\User;

/**
 * Собрано из фрагмента урока 13.4: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class DbUserRepository
{
    public function findByIds(array $ids): array
    {
        if ($ids === []) {
            return [];                      // без этого получится WHERE id IN () — ошибка SQL
        }

        $rows = (new Query($this->db))
            ->from('{{%user}}')
            // массив в значении превращается в IN (...) — один запрос на всех
            ->where(['id' => array_map(static fn (UserId $id): int => $id->value, $ids)])
            ->all();

        return array_map($this->mapper->toEntity(...), $rows);
    }
}
