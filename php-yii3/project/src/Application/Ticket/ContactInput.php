<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use Yiisoft\Validator\Rule\{Email, Length, Required};

final readonly class ContactInput
{
    public function __construct(
        #[Required]
        #[Email(message: 'Некорректный адрес электронной почты.')]
        public string $email = '',

        #[Length(max: 32)]
        public string $phone = '',
    ) {
    }
}
