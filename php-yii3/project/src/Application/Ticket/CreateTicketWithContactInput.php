<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use Yiisoft\Validator\Rule\{Each, Length, Nested, Required};

final readonly class CreateTicketWithContactInput
{
    /** @param list<ContactInput> $watchers */
    public function __construct(
        #[Required]
        #[Length(min: 5, max: 200)]
        public string $title = '',

        // Nested проверяет вложенный объект его собственными правилами
        #[Nested(ContactInput::class)]
        public ?ContactInput $contact = null,

        #[Each([new Nested(ContactInput::class)])]
        public array $watchers = [],
    ) {
    }
}
