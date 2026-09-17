<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\TicketFilter;
use App\Application\Ticket\TicketPage;
use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\Ticket\{Ticket, TicketId, TicketRepositoryInterface, TicketStatus};
use App\Domain\User\UserId;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Db\Query\Query;

final readonly class DbTicketRepository implements TicketRepositoryInterface
{
    private const TABLE = '{{%ticket}}';

    public function __construct(
        private ConnectionInterface $db,
        private TicketMapper $mapper,
    ) {
    }

    public function findById(TicketId $id): ?Ticket
    {
        $row = $this->baseQuery()->andWhere(['id' => $id->value])->one();

        return $row === null ? null : $this->mapper->toEntity($row);
    }

    public function getById(TicketId $id): Ticket
    {
        return $this->findById($id) ?? throw TicketNotFoundException::withId($id);
    }

    public function paginate(TicketFilter $filter): TicketPage
    {
        $query = $this->applyFilter($this->baseQuery(), $filter);

        // clone: без него orderBy и limit попадут в подсчёт
        $total = (int) (clone $query)->count();

        $rows = $query
            ->orderBy($this->sortToOrderBy($filter->sort))
            ->limit($filter->limit)
            ->offset($filter->offset)
            ->all();

        return new TicketPage(
            items: array_map($this->mapper->toEntity(...), $rows),
            total: $total,
            limit: $filter->limit,
            offset: $filter->offset,
        );
    }

    public function countOpenByAssignee(UserId $assigneeId): int
    {
        return (int) $this->baseQuery()
            ->andWhere([
                'assignee_id' => $assigneeId->value,
                'status' => [TicketStatus::Open->value, TicketStatus::InProgress->value,
                             TicketStatus::Waiting->value],
            ])
            ->count();
    }

    // findOverdue() и findByCursor() устроены так же: baseQuery() плюс
    // условия, порядок из белого списка и ограничение сверху.

    public function save(Ticket $ticket): void
    {
        $row = $this->mapper->toRow($ticket);

        if ($ticket->id->isNew()) {
            $this->db->createCommand()->insert(self::TABLE, $row)->execute();

            // без этого следующий save() вставит дубль вместо обновления
            $ticket->assignId(
                TicketId::fromInt((int) $this->db->getLastInsertID('ticket_id_seq')),
            );

            return;
        }

        $this->db->createCommand()
            ->update(self::TABLE, $row, ['id' => $ticket->id->value])
            ->execute();
    }

    public function remove(Ticket $ticket): void
    {
        // мягкое удаление: история обращений нужна для отчётности
        $this->db->createCommand()->update(
            self::TABLE,
            ['deleted_at' => (new \DateTimeImmutable())->format(\DateTimeInterface::ATOM)],
            ['id' => $ticket->id->value],
        )->execute();
    }

    /** Условие «не удалено» задано ОДИН раз: забыть его в новом методе трудно. */
    private function baseQuery(): Query
    {
        return (new Query($this->db))->from(self::TABLE)->where(['deleted_at' => null]);
    }

    private function applyFilter(Query $query, TicketFilter $filter): Query
    {
        // ограничение видимости — часть запроса, а не постобработка
        if ($filter->onlyReporterId !== null) {
            $query->andWhere(['reporter_id' => $filter->onlyReporterId]);
        }

        if ($filter->statusAsEnum() !== null) {
            $query->andWhere(['status' => $filter->statusAsEnum()->value]);
        }

        if ($filter->assigneeId !== null) {
            $query->andWhere(['assignee_id' => $filter->assigneeId]);
        }

        if ($filter->search !== '') {
            $query->andWhere(['ilike', 'title', $filter->search]);
        }

        return $query;
    }

    /**
     * Белый список: имя колонки и направление НЕ защищены привязкой параметров.
     * @return array<string, int>
     */
    private function sortToOrderBy(string $sort): array
    {
        return match ($sort) {
            'createdAt' => ['created_at' => SORT_ASC],
            '-createdAt' => ['created_at' => SORT_DESC],
            // вторичный ключ: иначе порядок внутри приоритета не определён
            'priority' => ['priority' => SORT_ASC, 'created_at' => SORT_DESC],
            '-priority' => ['priority' => SORT_DESC, 'created_at' => SORT_DESC],
            'title' => ['title' => SORT_ASC],
            default => ['created_at' => SORT_DESC],
        };
    }

    public function findAll(?TicketStatus $status = null, int $limit = 50, int $offset = 0): array
    {
        $query = (new Query($this->db))
            ->from(self::TABLE)
            ->orderBy(['created_at' => SORT_DESC])
            ->limit($limit)
            ->offset($offset);

        if ($status !== null) {
            $query->andWhere(['status' => $status->value]);
        }

        return array_map($this->hydrate(...), $query->all());
    }

    public function countAll(?TicketStatus $status = null): int
    {
        $query = (new Query($this->db))->from(self::TABLE);

        if ($status !== null) {
            $query->andWhere(['status' => $status->value]);
        }

        return (int) $query->count();
    }

    /** @param array<string, mixed> $row */
    private function hydrate(array $row): Ticket
    {
        return Ticket::fromState(
            id: TicketId::fromInt((int) $row['id']),
            title: (string) $row['title'],
            description: (string) $row['description'],
            status: TicketStatus::from((string) $row['status']),
            priority: TicketPriority::from((string) $row['priority']),
            reporterId: (int) $row['reporter_id'],
            assigneeId: $row['assignee_id'] === null
                ? null
                : UserId::fromInt((int) $row['assignee_id']),
            createdAt: new \DateTimeImmutable((string) $row['created_at']),
        );
    }

    /** @param list<Ticket> $tickets */
    public function saveMany(array $tickets): void
    {
    if ($tickets === []) {
        return;
    }

    // один запрос вместо N: разница на тысяче строк — секунды против минут
    $this->db->createCommand()->batchInsert(
        self::TABLE,
        ['title', 'description', 'status', 'priority', 'reporter_id', 'created_at'],
        array_map(static fn (Ticket $t): array => [
            $t->title, $t->description, $t->status->value, $t->priority->value,
            $t->reporterId, $t->createdAt->format(\DateTimeInterface::ATOM),
        ], $tickets),
    )->execute();
    }

    public function delete(TicketId $id): void
    {
    $this->db->createCommand()->delete(self::TABLE, ['id' => $id->value])->execute();
    }

    /** @return list<int> */
    public function findOverdueIds(\DateTimeImmutable $now): array
    {
        return array_map(intval(...), (new Query($this->db))
            ->select('id')
            ->from(self::TABLE)
            ->where(['<', 'sla_deadline', $now->format(\DateTimeInterface::ATOM)])
            ->andWhere(['not', ['status' => TicketStatus::Closed->value]])
            ->column());
    }

    /** @return list<Ticket> */
    public function findByFilter(TicketFilter $filter): array
    {
    $query = (new Query($this->db))->from(self::TABLE);

    // andWhere вызывается только для заданных фильтров
    if ($filter->statusAsEnum() !== null) {
        $query->andWhere(['status' => $filter->statusAsEnum()->value]);
    }

    if ($filter->assigneeId !== null) {
        $query->andWhere(['assignee_id' => $filter->assigneeId]);
    }

    if ($filter->search !== '') {
        // ILIKE — регистронезависимый поиск PostgreSQL
        $query->andWhere(['ilike', 'title', $filter->search]);
    }

    return array_map(
        $this->hydrate(...),
        $query
            ->orderBy($this->sortToOrderBy($filter->sort))
            ->limit($filter->limit)
            ->offset($filter->offset)
            ->all(),
    );
    }

    /**
    * Чтение с блокировкой строки: второй параллельный сценарий
    * подождёт, пока первый зафиксируется.
    */
    public function findByIdForUpdate(TicketId $id): ?Ticket
    {
    $row = $this->db->createCommand(
        'SELECT * FROM {{%ticket}} WHERE id = :id FOR UPDATE',
        [':id' => $id->value],
    )->queryOne();

    return $row === false || $row === null ? null : $this->hydrate($row);
    }

    /** Отдельный метод для администратора и отчётов. */
    public function findByIdIncludingDeleted(TicketId $id): ?Ticket
    {
    $row = (new Query($this->db))
        ->from(self::TABLE)
        ->where(['id' => $id->value])
        ->one();

    return $row === null ? null : $this->mapper->toEntity($row);
    }

    public function findWithComments(TicketId $id): ?TicketWithComments
    {
    $row = $this->baseQuery()->andWhere(['id' => $id->value])->one();

    if ($row === null) {
        return null;
    }

    // комментарии одним запросом, вместе с авторами через JOIN:
    // здесь связь «многие к одному», JOIN уместен
    $comments = (new Query($this->db))
        ->select(['c.*', 'author_name' => 'u.name', 'author_email' => 'u.email'])
        ->from(['c' => '{{%comment}}'])
        ->leftJoin(['u' => '{{%user}}'], 'u.id = c.author_id')
        ->where(['c.ticket_id' => $id->value])
        ->orderBy(['c.created_at' => SORT_ASC])
        ->all();

    return new TicketWithComments(
        ticket: $this->mapper->toEntity($row),
        comments: array_map($this->commentMapper->toEntity(...), $comments),
    );
    }

    public function paginateByCursor(TicketFilter $filter, ?TicketCursor $after): TicketCursorPage
    {
    $query = $this->applyFilter($this->baseQuery(), $filter)
        // порядок должен совпадать с составом курсора
        ->orderBy(['created_at' => SORT_DESC, 'id' => SORT_DESC])
        // берём на одну больше, чтобы узнать о наличии следующей страницы
        ->limit($filter->limit + 1);

    if ($after !== null) {
        // сравнение кортежей: строго после указанной позиции
        $query->andWhere(
            '(created_at, id) < (:cursorDate, :cursorId)',
            [
                ':cursorDate' => $after->createdAt->format(\DateTimeInterface::ATOM),
                ':cursorId' => $after->id,
            ],
        );
    }

    $rows = $query->all();

    $hasMore = count($rows) > $filter->limit;
    $rows = array_slice($rows, 0, $filter->limit);

    $items = array_map($this->mapper->toEntity(...), $rows);
    $last = $items === [] ? null : $items[array_key_last($items)];

    return new TicketCursorPage(
        items: $items,
        nextCursor: $hasMore && $last !== null
            ? (new TicketCursor($last->createdAt, $last->id->value))->encode()
            : null,
        hasMore: $hasMore,
    );
    }

    public function assign(TicketId $ticketId, User $assignee): void
    {
    $this->db->createCommand()
        ->update(
            'ticket',
            [
                'assignee' => $assignee->email,      // старая: нужна для отката
                'assignee_id' => $assignee->id,      // новая: нужна следующему релизу
                'updated_at' => (new \DateTimeImmutable())->format(\DateTimeInterface::ATOM),
            ],
            ['id' => $ticketId->value],
        )
        ->execute();
    }
}
