<?php
// app/Http/Requests/LoginRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

final class LoginRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'email'    => ['required', 'email', 'max:255'],
            'password' => ['required', 'string'],
            'device'   => ['sometimes', 'string', 'max:100'],
        ];
    }

    public function device(): string
    {
        return $this->string('device', 'api')->limit(100, '')->toString();
    }
}
