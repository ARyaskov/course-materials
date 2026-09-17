<?php
// app/Http/Queries/TicketQuery.php
declare(strict_types=1);

namespace App\Http\Queries;

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

final readonly class TicketQuery
{
    private const int DEFAULT_PER_PAGE = 20;
    private const int MAX_PER_PAGE = 100;

    /** Разрешённые поля сортировки: имя из API → колонка в БД. */
    private const array SORTABLE = [
        'created_at' => 'created_at',
        'updated_at' => 'updated_at',
        'priority'   => 'priority',
        'subject'    => 'subject',
    ];

    private const array INCLUDABLE = ['author', 'assignee', 'tags'];

    public function __construct(private Request $request, private User $user)
    {
    }

    public function paginate(): LengthAwarePaginator
    {
        return $this->baseQuery()
            ->with($this->includes())
            ->withCount('comments')
            ->tap($this->applyFilters(...))
            ->tap($this->applySorting(...))
            ->paginate($this->perPage())
            ->withQueryString();
    }

    private function baseQuery(): Builder
    {
        return Ticket::query()
            // права доступа — часть базового запроса, а не фильтр
            ->unless($this->user->isAgent(), fn (Builder $q) => $q->where('author_id', $this->user->id));
    }

    private function applyFilters(Builder $query): void
    {
        $r = $this->request;

        $query
            ->when($r->enum('status', TicketStatus::class), fn (Builder $q, $s) => $q->where('status', $s))
            ->when($r->array('priority'), function (Builder $q, array $values): void {
                $priorities = array_filter(array_map(TicketPriority::tryFrom(...), $values));

                if ($priorities !== []) {
                    $q->whereIn('priority', $priorities);
                }
            })
            ->when($r->integer('assignee_id'), fn (Builder $q, int $id) => $q->where('assignee_id', $id))
            ->when($r->boolean('unassigned'), fn (Builder $q) => $q->whereNull('assignee_id'))
            ->when($r->date('created_from'), fn (Builder $q, $d) => $q->where('created_at', '>=', $d))
            ->when($r->date('created_to'), fn (Builder $q, $d) => $q->where('created_at', '<=', $d))
            ->when($r->string('q')->trim()->toString(), function (Builder $q, string $term): void {
                $q->where(fn (Builder $inner) => $inner
                    ->where('subject', 'ilike', '%' . addcslashes($term, '%_\\') . '%')
                    ->orWhere('body', 'ilike', '%' . addcslashes($term, '%_\\') . '%'));
            })
            ->when($r->array('tags'), fn (Builder $q, array $slugs) => $q->whereHas(
                'tags',
                fn (Builder $t) => $t->whereIn('slug', $slugs),
            ));
    }

    private function applySorting(Builder $query): void
    {
        $sort = $this->request->string('sort', '-created_at')->toString();

        $descending = str_starts_with($sort, '-');
        $field = ltrim($sort, '-');

        $column = self::SORTABLE[$field] ?? 'created_at';

        $query->orderBy($column, $descending ? 'desc' : 'asc')
            ->orderBy('id', 'desc');   // стабильный порядок при равных значениях
    }

    /** @return list<string> */
    private function includes(): array
    {
        return array_values(array_intersect($this->request->array('include'), self::INCLUDABLE));
    }

    private function perPage(): int
    {
        return min(max($this->request->integer('per_page', self::DEFAULT_PER_PAGE), 1), self::MAX_PER_PAGE);
    }
}
