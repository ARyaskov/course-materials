<?php
// app/Http/Requests/TicketIndexRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use App\DTO\TicketFilters;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

final class TicketIndexRequest extends FormRequest
{
    private const array SORTABLE = ['created_at', 'updated_at', 'priority', 'subject'];

    public function rules(): array
    {
        return [
            'status'      => ['sometimes', Rule::enum(TicketStatus::class)],
            'priority'    => ['sometimes', 'array', 'max:4'],
            'priority.*'  => [Rule::enum(TicketPriority::class)],
            'assignee_id' => ['sometimes', 'nullable', 'integer', 'exists:users,id'],
            'unassigned'  => ['sometimes', 'boolean'],
            'unanswered'  => ['sometimes', 'boolean'],
            'created_from'=> ['sometimes', 'date'],
            'created_to'  => ['sometimes', 'date', 'after_or_equal:created_from'],
            'q'           => ['sometimes', 'string', 'min:2', 'max:100'],
            'sort'        => ['sometimes', 'string', Rule::in($this->allowedSorts())],
            'per_page'    => ['sometimes', 'integer', 'between:1,100'],
            'cursor'      => ['sometimes', 'string'],
            'include'     => ['sometimes', 'array'],
            'include.*'   => [Rule::in(['author', 'assignee', 'tags'])],
        ];
    }

    /** @return list<string> */
    private function allowedSorts(): array
    {
        return array_merge(
            self::SORTABLE,
            array_map(static fn (string $f): string => '-' . $f, self::SORTABLE),
        );
    }

    public function toFilters(): TicketFilters
    {
        return TicketFilters::fromRequest($this);
    }

    public function perPage(): int
    {
        return $this->integer('per_page', 20);
    }

    public function sort(): string
    {
        return $this->string('sort', '-created_at')->toString();
    }

    /** @return list<string> */
    public function includes(): array
    {
        return array_values(array_intersect($this->array('include'), ['author', 'assignee', 'tags']));
    }
}
