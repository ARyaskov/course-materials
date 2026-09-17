<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

final readonly class TicketId
{
    private function __construct(public int $value)
    {
        if ($value < 0) {
            throw new \InvalidArgumentException('Идентификатор заявки не может быть отрицательным.');
        }
    }

    public static function fromInt(int $value): self
    {
        return new self($value);
    }

    /** Новая, ещё не сохранённая заявка: идентификатор присвоит база. */
    public static function next(): self
    {
        return new self(0);
    }

    public function isNew(): bool
    {
        return $this->value === 0;
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }
}
