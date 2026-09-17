<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\TicketFilter;
use App\Application\Ticket\TicketListItem;
use App\Domain\User\{User, UserId, UserRepositoryInterface};
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Db\Query\Query;

final readonly class DbTicketQueryRepository
{
    public function __construct(
        private ConnectionInterface $db,
        private UserRepositoryInterface $users,
        private TicketMapper $mapper,
    ) {
    }

    /** @return list<TicketListItem> */
    public function listWithAssignees(TicketFilter $filter): array
    {
        // запрос 1: сами заявки
        $rows = $this->baseQuery($filter)->all();

        if ($rows === []) {
            return [];
        }

        // запрос 2: все исполнители разом, а не по одному
        $assigneeIds = array_values(array_unique(array_filter(
            array_column($rows, 'assignee_id'),
            static fn (mixed $id): bool => $id !== null,
        )));

        $users = $this->users->findByIds(
            array_map(static fn (int $id): UserId => UserId::fromInt($id), $assigneeIds),
        );

        // индексируем по id: доступ за O(1) вместо поиска по массиву
        $usersById = [];

        foreach ($users as $user) {
            $usersById[$user->id->value] = $user;
        }

        return array_map(
            fn (array $row): TicketListItem => new TicketListItem(
                ticket: $this->mapper->toEntity($row),
                assignee: $row['assignee_id'] === null
                    ? null
                    : ($usersById[(int) $row['assignee_id']] ?? null),
            ),
            $rows,
        );
    }

    /** @return list<array<string, mixed>> */
    public function listWithAssigneesJoined(TicketFilter $filter): array
    {
    return (new Query($this->db))
        ->select([
            't.*',
            'assignee_name' => 'u.name',
            'assignee_email' => 'u.email',
        ])
        ->from(['t' => '{{%ticket}}'])
        ->leftJoin(['u' => '{{%user}}'], 'u.id = t.assignee_id')
        ->where(['t.deleted_at' => null])
        ->orderBy(['t.created_at' => SORT_DESC])
        ->limit($filter->limit)
        ->offset($filter->offset)
        ->all();
    }
}
