<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use Yiisoft\Validator\Rule\Integer;
use Yiisoft\Validator\Rule\Required;

final readonly class AssignTicketInput
{
    public function __construct(
        #[Required(message: 'Укажите идентификатор ответственного.')]
        #[Integer(min: 1, message: 'Некорректный идентификатор ответственного.')]
        public ?int $assigneeId = null,

        #[Length(max: 500)]
        public string $comment = '',
    ) {
    }
}
