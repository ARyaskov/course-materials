<?php
// app/Http/Requests/CloseTicketRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

final class CloseTicketRequest extends ApiRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('close', $this->route('ticket'));
    }

    public function rules(): array
    {
        return ['resolution' => ['nullable', 'string', 'max:2000']];
    }

    public function resolution(): ?string
    {
        return $this->filled('resolution') ? $this->string('resolution')->trim()->toString() : null;
    }
}
