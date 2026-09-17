<?php
// app/Http/Requests/UpdateTicketRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use App\Enums\TicketPriority;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

final class UpdateTicketRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('ticket'));
    }

    public function rules(): array
    {
        // PUT заменяет ресурс целиком, PATCH меняет часть
        $presence = $this->isMethod('put') ? 'required' : 'sometimes';

        return [
            'subject'  => [$presence, 'string', 'min:5', 'max:200'],
            'body'     => [$presence, 'string', 'min:10', 'max:10000'],
            'priority' => [$presence, Rule::enum(TicketPriority::class)],

            // null означает «снять исполнителя»
            'assignee_id' => ['sometimes', 'nullable', 'integer', 'exists:users,id'],

            // статусом управляет сервер через отдельные действия
            'status' => ['prohibited'],
        ];
    }

    public function messages(): array
    {
        return [
            'status.prohibited' => 'Статус меняется через действия /close и /reopen.',
        ];
    }
}
