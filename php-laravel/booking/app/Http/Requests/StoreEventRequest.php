<?php
// app/Http/Requests/StoreEventRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use App\Models\Event;
use Illuminate\Foundation\Http\FormRequest;

final class StoreEventRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Event::class);
    }

    public function rules(): array
    {
        return [
            'title' => ['required', 'string', 'min:5', 'max:200'],
            'description' => ['required', 'string', 'min:20', 'max:10000'],
            'venue' => ['required', 'string', 'max:200'],
            'capacity' => ['required', 'integer', 'min:1', 'max:10000'],
            'price' => ['required', 'integer', 'min:0', 'max:100000000'],
            'starts_at' => ['required', 'date', 'after:+1 hour'],
            'ends_at' => ['required', 'date', 'after:starts_at'],
        ];
    }

    public function messages(): array
    {
        return [
            'starts_at.after' => 'Мероприятие должно начинаться не раньше чем через час.',
            'ends_at.after' => 'Окончание должно быть позже начала.',
        ];
    }
}
