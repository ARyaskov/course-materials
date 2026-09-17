<?php
// app/Queries/TicketQuery.php
declare(strict_types=1);

namespace App\Queries;

use App\DTO\TicketFilters;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Contracts\Pagination\Paginator;
use Illuminate\Database\Eloquent\Builder;

final readonly class TicketQuery
{
    private const array SORT_MAP = [
        'created_at' => 'created_at',
        'updated_at' => 'updated_at',
        'priority'   => 'priority',
        'subject'    => 'subject',
    ];

    /** @param  list<string>  $includes */
    public function __construct(
        private TicketFilters $filters,
        private User $user,
        private array $includes = [],
        private string $sort = '-created_at',
    ) {
    }

    public function paginate(int $perPage): Paginator
    {
        return $this->build()->paginate($perPage)->withQueryString();
    }

    public function cursorPaginate(int $perPage): Paginator
    {
        return $this->build()->cursorPaginate($perPage);
    }

    /** @return array<string, int> */
    public function countsByStatus(): array
    {
        return Ticket::query()
            ->visibleTo($this->user)
            ->groupBy('status')
            ->selectRaw('status, count(*) as total')
            ->pluck('total', 'status')
            ->all();
    }

    private function build(): Builder
    {
        $f = $this->filters;

        return Ticket::query()
            ->visibleTo($this->user)
            ->with($this->relations())
            ->withCount([
                'comments',
                'comments as agent_replies_count' => fn (Builder $q) => $q->whereHas(
                    'author',
                    fn (Builder $a) => $a->where('role', 'agent'),
                ),
            ])
            ->withExists('attachments')
            ->when($f->status, fn (Builder $q, $s) => $q->where('status', $s))
            ->when($f->priorities !== [], fn (Builder $q) => $q->whereIn('priority', $f->priorities))
            ->when($f->assigneeId, fn (Builder $q, int $id) => $q->where('assignee_id', $id))
            ->when($f->unassignedOnly, fn (Builder $q) => $q->whereNull('assignee_id'))
            ->when($f->unansweredOnly, fn (Builder $q) => $q->unanswered())
            ->when($f->createdFrom, fn (Builder $q, $d) => $q->where('created_at', '>=', $d))
            ->when($f->createdTo, fn (Builder $q, $d) => $q->where('created_at', '<=', $d))
            ->when($f->search, fn (Builder $q, string $term) => $q->where(
                fn (Builder $i) => $i
                    ->where('subject', 'ilike', '%' . addcslashes($term, '%_\\') . '%')
                    ->orWhere('body', 'ilike', '%' . addcslashes($term, '%_\\') . '%')
            ))
            ->tap($this->applySort(...));
    }

    /** @return array<string, \Closure|string> */
    private function relations(): array
    {
        $map = [
            'author'   => 'author:id,name,role',
            'assignee' => 'assignee:id,name,role',
            'tags'     => 'tags:id,slug,name,color',
        ];

        // автор нужен всегда — иначе список порождает N+1
        $selected = array_unique([...$this->includes, 'author']);

        return array_values(array_intersect_key($map, array_flip($selected)));
    }

    private function applySort(Builder $query): void
    {
        $descending = str_starts_with($this->sort, '-');
        $field = ltrim($this->sort, '-');

        $query->orderBy(self::SORT_MAP[$field] ?? 'created_at', $descending ? 'desc' : 'asc')
            ->orderByDesc('id');   // стабильный порядок
    }
}
