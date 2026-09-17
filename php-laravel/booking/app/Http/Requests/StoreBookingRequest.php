<?php
// app/Http/Requests/StoreBookingRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

final class StoreBookingRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'seats' => ['required', 'integer', 'min:1', 'max:10'],
        ];
    }
}
