<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;

final class InvalidAttachmentException extends DomainException
{
    public static function tooLarge(int $maxBytes): self
    {
        return new self(sprintf('Файл больше %d байт.', $maxBytes));
    }

    public static function forbiddenType(string $mime): self
    {
        return new self(sprintf('Тип %s не разрешён.', $mime));
    }

    public function errorType(): string
    {
        return 'invalid_attachment';
    }
}
