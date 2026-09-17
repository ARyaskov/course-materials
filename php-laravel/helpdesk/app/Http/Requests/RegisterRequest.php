<?php
// app/Http/Requests/RegisterRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

final class RegisterRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'name'     => ['required', 'string', 'min:2', 'max:100'],
            // dns-проверка и обращение к базе утечек — только в боевой среде:
            // в тестах и разработке они делают сеть обязательной
            'email' => [
                'required',
                app()->isProduction() ? 'email:rfc,dns' : 'email:rfc',
                'max:255',
                Rule::unique('users', 'email'),
            ],
            'password' => ['required', 'confirmed', Password::defaults()],

            'role' => ['prohibited'],
        ];
    }

    public function messages(): array
    {
        return [
            'role.prohibited' => 'Роль назначается администратором.',
            'email.unique'    => 'Пользователь с таким адресом уже зарегистрирован.',
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge(['email' => mb_strtolower(trim((string) $this->input('email')))]);
    }
}
