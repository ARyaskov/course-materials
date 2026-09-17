<?php
// app/Http/Requests/StoreTicketRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use App\DTO\TicketData;
use App\Enums\TicketPriority;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use App\Rules\NotProfane;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

final class StoreTicketRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Ticket::class);
    }

    public function rules(): array
    {
        return [
            'subject'  => ['bail', 'required', 'string', 'min:5', 'max:200', new NotProfane()],
            'body'     => ['bail', 'required', 'string', 'min:10', 'max:10000'],
            'priority' => ['sometimes', Rule::enum(TicketPriority::class)],
            'tags'     => ['sometimes', 'array', 'max:5'],
            'tags.*'   => ['string', 'distinct', 'max:50'],
            'assignee_id' => ['bail', 'nullable', 'integer'],
            'due_at'   => ['nullable', 'date', 'after:now', 'before:+1 year'],
            'status'   => ['prohibited'],
        ];
    }

    public function after(): array
    {
        return [
            $this->checkOpenTicketsLimit(...),
            $this->checkTagsExist(...),
            $this->checkAssigneeIsAgent(...),
            $this->checkCriticalRequiresAssignee(...),
        ];
    }

    private function checkOpenTicketsLimit(Validator $validator): void
    {
        $limit = config('helpdesk.limits.open_tickets_per_user');

        $current = Ticket::query()
            ->where('author_id', $this->user()->id)
            ->whereNot('status', 'closed')
            ->count();

        if ($current >= $limit) {
            $validator->errors()->add(
                'subject',
                "Превышен лимит открытых заявок: {$current} из {$limit}. Закройте часть заявок.",
            );
        }
    }

    private function checkTagsExist(Validator $validator): void
    {
        $slugs = $this->array('tags');

        if ($slugs === [] || $validator->errors()->has('tags')) {
            return;
        }

        // одна проверка вместо N запросов через exists
        $found = Tag::query()->whereIn('slug', $slugs)->pluck('slug')->all();

        foreach (array_diff($slugs, $found) as $slug) {
            $validator->errors()->add('tags', "Метка «{$slug}» не найдена.");
        }
    }

    private function checkAssigneeIsAgent(Validator $validator): void
    {
        $id = $this->input('assignee_id');

        if ($id === null || $validator->errors()->has('assignee_id')) {
            return;
        }

        $isAgent = User::query()
            ->whereKey($id)
            ->whereIn('role', ['agent', 'admin'])
            ->exists();

        if (! $isAgent) {
            $validator->errors()->add('assignee_id', 'Исполнителем может быть только сотрудник поддержки.');
        }
    }

    private function checkCriticalRequiresAssignee(Validator $validator): void
    {
        if ($this->input('priority') === 'critical' && $this->input('assignee_id') === null) {
            $validator->errors()->add('assignee_id', 'Критичная заявка требует исполнителя.');
        }
    }

    public function toData(): TicketData
    {
        return TicketData::fromRequest($this);
    }
}
