<?php
// app/Http/Requests/IndexEventRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

final class IndexEventRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'search' => ['nullable', 'string', 'min:2', 'max:100'],
            'venue' => ['nullable', 'string', 'max:100'],
            'price_max' => ['nullable', 'integer', 'min:0'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date', 'after_or_equal:from'],
            'available' => ['nullable', 'boolean'],
            'sort' => ['nullable', Rule::in(['starts_at', '-starts_at', 'price', '-price', '-created_at'])],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
            'cursor' => ['nullable', 'string'],
        ];
    }

    public function filters(): array
    {
        return $this->safe()->except(['per_page', 'cursor']);
    }

    public function perPage(): int
    {
        return (int) $this->validated('per_page', 20);
    }
}
