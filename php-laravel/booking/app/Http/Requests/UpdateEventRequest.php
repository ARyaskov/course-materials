<?php
// app/Http/Requests/UpdateEventRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

final class UpdateEventRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('event'));
    }

    public function rules(): array
    {
        return [
            'title' => ['sometimes', 'string', 'min:5', 'max:200'],
            'description' => ['sometimes', 'string', 'min:20', 'max:10000'],
            'venue' => ['sometimes', 'string', 'max:200'],
            'capacity' => ['sometimes', 'integer', 'min:1', 'max:10000'],
            'price' => ['sometimes', 'integer', 'min:0'],
            'starts_at' => ['sometimes', 'date', 'after:+1 hour'],
            'ends_at' => ['sometimes', 'date', 'after:starts_at'],
        ];
    }

    public function after(): array
    {
        return [
            // Р6: вместимость нельзя опустить ниже уже занятых мест
            function (Validator $validator): void {
                $capacity = $this->integer('capacity');

                if (! $this->has('capacity')) {
                    return;
                }

                $occupied = $this->route('event')->occupiedSeats();

                if ($capacity < $occupied) {
                    $validator->errors()->add(
                        'capacity',
                        "Уже занято мест: {$occupied}. Вместимость не может быть меньше."
                    );
                }
            },
        ];
    }
}
