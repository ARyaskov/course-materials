<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Db\Query\Query;

final readonly class DbWatcherRepository
{
    public function __construct(private ConnectionInterface $db)
    {
    }

    /**
     * Наблюдатели сразу для нескольких заявок — один запрос вместо N.
     * @param list<TicketId> $ticketIds
     * @return array<int, list<int>> ticketId → список userId
     */
    public function findWatcherIdsForTickets(array $ticketIds): array
    {
        if ($ticketIds === []) {
            return [];
        }

        $rows = (new Query($this->db))
            ->select(['ticket_id', 'user_id'])
            ->from('{{%ticket_watcher}}')
            ->where(['ticket_id' => array_map(
                static fn (TicketId $id): int => $id->value,
                $ticketIds,
            )])
            ->all();

        $grouped = [];

        foreach ($rows as $row) {
            $grouped[(int) $row['ticket_id']][] = (int) $row['user_id'];
        }

        return $grouped;
    }

    public function add(TicketId $ticketId, UserId $userId): void
    {
        // ON CONFLICT DO NOTHING: повторное добавление не ошибка
        $this->db->createCommand(
            'INSERT INTO {{%ticket_watcher}} (ticket_id, user_id)
             VALUES (:ticket, :user) ON CONFLICT DO NOTHING',
            [':ticket' => $ticketId->value, ':user' => $userId->value],
        )->execute();
    }
}
