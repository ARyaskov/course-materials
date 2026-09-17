<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

final readonly class AttachmentId
{
    private function __construct(public int $value)
    {
        if ($value <= 0) {
            throw new \InvalidArgumentException('Идентификатор вложения должен быть положительным.');
        }
    }

    public static function fromInt(int $value): self
    {
        return new self($value);
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }
}
