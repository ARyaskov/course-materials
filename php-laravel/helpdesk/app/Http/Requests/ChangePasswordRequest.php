<?php
// app/Http/Requests/ChangePasswordRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Password;

final class ChangePasswordRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'current_password' => ['required', 'current_password:sanctum'],
            'password'         => [
                'required',
                'confirmed',
                'different:current_password',
                Password::min(12)->letters()->mixedCase()->numbers()->uncompromised(),
            ],
        ];
    }
}
