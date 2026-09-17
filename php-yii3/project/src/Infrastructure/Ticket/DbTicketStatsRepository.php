<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use Yiisoft\Db\Connection\ConnectionInterface;

final readonly class DbTicketStatsRepository
{
    public function __construct(private ConnectionInterface $db)
    {
    }

    /**
     * Оконная функция: доля заявок каждого приоритета.
     * Построителем такое выражается хуже, чем прямым SQL.
     *
     * @return list<array{priority: string, total: int, share: float}>
     */
    public function priorityDistribution(\DateTimeImmutable $since): array
    {
        return $this->db->createCommand(
            <<<'SQL'
            SELECT priority,
                   count(*) AS total,
                   round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS share
            FROM {{%ticket}}
            WHERE created_at >= :since
            GROUP BY priority
            ORDER BY total DESC
            SQL,
            // параметр привязан — интерполяции в текст запроса нет
            [':since' => $since->format(\DateTimeInterface::ATOM)],
        )->queryAll();
    }

    /** Вставка с обновлением при конфликте — специфика PostgreSQL. */
    public function upsertDailyCounter(\DateTimeImmutable $day, int $delta): void
    {
        $this->db->createCommand(
            <<<'SQL'
            INSERT INTO {{%ticket_daily_stat}} (day, opened)
            VALUES (:day, :delta)
            ON CONFLICT (day) DO UPDATE SET opened = {{%ticket_daily_stat}}.opened + :delta
            SQL,
            [':day' => $day->format('Y-m-d'), ':delta' => $delta],
        )->execute();
    }
}
