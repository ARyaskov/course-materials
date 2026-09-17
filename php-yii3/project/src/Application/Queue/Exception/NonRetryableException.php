<?php

declare(strict_types=1);

namespace App\Application\Queue\Exception;

/** Маркер: повторять бессмысленно, сразу в failed. */
final class NonRetryableException extends \RuntimeException
{
    public static function invalidPayload(string $type, string $reason): self
    {
        return new self(sprintf('Некорректный payload %s: %s', $type, $reason));
    }
}
