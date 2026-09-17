<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\TicketPriority;
use Yiisoft\Validator\Rule\{Each, In, Integer, Length, Regex, Required};

final readonly class CreateTicketInput
{
    /** @param list<string> $tags */
    public function __construct(
        #[Required(message: 'Укажите тему заявки.')]
        #[Length(
            min: 5,
            max: 200,
            lessThanMinMessage: 'Тема должна быть не короче {min} символов.',
            greaterThanMaxMessage: 'Тема должна быть не длиннее {max} символов.',
        )]
        public string $title = '',

        #[Required(message: 'Опишите проблему.')]
        #[Length(min: 10, max: 5000)]
        public string $description = '',

        #[Required]
        #[In(
            ['low', 'normal', 'high', 'critical'],
            message: 'Недопустимый приоритет: {value}. Возможные: low, normal, high, critical.',
        )]
        public string $priority = 'normal',

        #[Integer(min: 1, message: 'Некорректный идентификатор ответственного.')]
        public ?int $assigneeId = null,

        // Each применяет вложенные правила к каждому элементу массива
        #[Each([
            new Length(min: 2, max: 32),
            new Regex('/^[\p{L}\d\-]+$/u', message: 'Метка содержит недопустимые символы.'),
        ])]
        public array $tags = [],
    ) {
    }

    public function priorityAsEnum(): TicketPriority
    {
        return TicketPriority::from($this->priority);
    }

    public function getRules(): iterable
    {
        return [
            'title' => [
                new Required(message: 'Укажите тему заявки.'),
                new Length(min: 5, max: 200),
            ],
            'description' => [
                new Required(message: 'Опишите проблему.'),
                new Length(min: 10, max: 5000),
            ],
            'priority' => [
                new Required(),
                // источник истины один — само перечисление
                new In(TicketPriority::values(), message: 'Недопустимый приоритет: {value}.'),
            ],
            'assigneeId' => [new Integer(min: 1)],
        ];
    }
}
