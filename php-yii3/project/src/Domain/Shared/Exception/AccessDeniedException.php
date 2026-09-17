<?php

declare(strict_types=1);

namespace App\Domain\Shared\Exception;

use App\Api\Error\ErrorType;
use App\Domain\Ticket\TicketId;

final class AccessDeniedException extends DomainException
{
    private function __construct(string $message, private readonly ErrorType $type)
    {
        parent::__construct($message);
    }

    /**
     * Для чужого объекта отвечаем как для несуществующего:
     * клиент не должен различать «нет» и «не ваше».
     */
    public static function forTicket(TicketId $id): self
    {
        return new self(
            sprintf('Заявка %d не найдена.', $id->value),
            ErrorType::TicketNotFound,
        );
    }

    /** Для операции над доступным объектом — честный 403. */
    public static function missingPermission(string $permission): self
    {
        return new self('Недостаточно прав.', ErrorType::AccessDenied);
    }

    public function errorType(): ErrorType
    {
        return $this->type;
    }
}
