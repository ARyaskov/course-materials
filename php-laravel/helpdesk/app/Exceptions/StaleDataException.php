<?php
// app/Exceptions/StaleDataException.php
declare(strict_types=1);

namespace App\Exceptions;

final class StaleDataException extends DomainException
{
    public function __construct(
        private readonly int $ticketId,
        private readonly int $expectedVersion,
    ) {
        parent::__construct('Заявка изменена другим пользователем. Обновите данные.');
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'stale_data';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 409;
    }

    #[\Override]
    public function context(): array
    {
        return ['ticket_id' => $this->ticketId, 'expected_version' => $this->expectedVersion];
    }
}
