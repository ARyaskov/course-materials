<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\{TicketId, TicketSearchInterface};
use Yiisoft\Db\Connection\ConnectionInterface;

final readonly class DbTicketSearch implements TicketSearchInterface
{
    public function __construct(private ConnectionInterface $db)
    {
    }

    public function search(string $query, int $limit = 50): array
    {
        $rows = $this->db->createCommand(
            'SELECT id FROM {{%ticket}}
             WHERE deleted_at IS NULL AND title ILIKE :q
             ORDER BY similarity(title, :raw) DESC
             LIMIT :limit',
            [':q' => '%' . $query . '%', ':raw' => $query, ':limit' => $limit],
        )->queryColumn();

        return array_map(TicketId::fromInt(...), array_map(intval(...), $rows));
    }

    // индексация не нужна: индекс поддерживает сама база
    public function index(Ticket $ticket): void
    {
    }

    public function remove(TicketId $id): void
    {
    }
}
