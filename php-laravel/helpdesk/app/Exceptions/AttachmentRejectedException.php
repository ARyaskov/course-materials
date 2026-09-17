<?php

declare(strict_types=1);

namespace App\Exceptions;

final class AttachmentRejectedException extends DomainException
{
    public function __construct(
        private readonly string $reason,
        private readonly ?string $filename = null,
    ) {
        parent::__construct("Файл отклонён: {$reason}");
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'attachment_rejected';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 422;
    }

    #[\Override]
    public function context(): array
    {
        return array_filter([
            'reason' => $this->reason,
            'filename' => $this->filename,
        ]);
    }

    #[\Override]
    public function hint(): string
    {
        return 'Допустимы PNG, JPEG, PDF и TXT до 16 МБ.';
    }
}
