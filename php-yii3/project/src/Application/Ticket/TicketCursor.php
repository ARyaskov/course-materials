<?php

declare(strict_types=1);

namespace App\Application\Ticket;

/**
 * Курсор — пара «дата создания + id». Второе поле разрывает ничью,
 * когда несколько заявок созданы в одну миллисекунду.
 */
final readonly class TicketCursor
{
    public function __construct(
        public \DateTimeImmutable $createdAt,
        public int $id,
    ) {
    }

    public function encode(): string
    {
        return rtrim(strtr(base64_encode(sprintf(
            '%s|%d',
            $this->createdAt->format(\DateTimeInterface::ATOM),
            $this->id,
        )), '+/', '-_'), '=');
    }

    public static function decode(string $cursor): ?self
    {
        $raw = base64_decode(strtr($cursor, '-_', '+/'), true);

        if ($raw === false || !str_contains($raw, '|')) {
            return null;                    // битый курсор — не ошибка, читаем с начала
        }

        [$date, $id] = explode('|', $raw, 2);

        try {
            return new self(new \DateTimeImmutable($date), (int) $id);
        } catch (\Exception) {
            return null;
        }
    }
}
