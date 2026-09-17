<?php

declare(strict_types=1);

namespace App\Domain\User;

final readonly class UserId
{
    private function __construct(public int $value)
    {
        if ($value < 0) {
            throw new \InvalidArgumentException('Идентификатор пользователя не может быть отрицательным.');
        }
    }

    public static function fromInt(int $value): self
    {
        return new self($value);
    }

    /** Новый, ещё не сохранённый пользователь: идентификатор присвоит база. */
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
