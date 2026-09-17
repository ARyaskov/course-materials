<?php

declare(strict_types=1);

namespace App\Application\User;

use App\Infrastructure\Validation\Rule\NotCompromisedPassword;
use Yiisoft\Validator\Rule\{Email, Length, Regex, Required};

final readonly class RegisterUserInput
{
    public function __construct(
        #[Required]
        #[Email]
        public string $email = '',

        #[Required]
        #[Length(min: 2, max: 120)]
        public string $name = '',

        #[Required(message: 'Укажите пароль.')]
        // длина важнее состава символов: 12 символов сильнее, чем 8 со спецсимволом
        #[Length(min: 12, max: 200, lessThanMinMessage: 'Пароль короче {min} символов.')]
        #[NotCompromisedPassword]
        public string $plainPassword = '',
    ) {
    }

    /** Пароль не должен попасть в лог при отладочном выводе объекта. */
    public function __debugInfo(): array
    {
        return ['email' => $this->email, 'name' => $this->name,
                'plainPassword' => '***'];
    }
}
