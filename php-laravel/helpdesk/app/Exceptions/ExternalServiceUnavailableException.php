<?php
// app/Exceptions/ExternalServiceUnavailableException.php
declare(strict_types=1);

namespace App\Exceptions;

final class ExternalServiceUnavailableException extends DomainException
{
    public function __construct(
        public readonly string $service,
        ?\Throwable $previous = null,
    ) {
        parent::__construct("Сервис «{$service}» временно недоступен", 0, $previous);
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'service_unavailable';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 503;
    }

    #[\Override]
    public function context(): array
    {
        return ['service' => $this->service, 'cause' => $this->getPrevious()?->getMessage()];
    }

    #[\Override]
    public function hint(): string
    {
        return 'Повторите запрос через несколько минут.';
    }
}
