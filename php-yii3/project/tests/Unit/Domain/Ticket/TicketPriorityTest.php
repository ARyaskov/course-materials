<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Ticket;

use App\Domain\Ticket\TicketPriority;
use PHPUnit\Framework\Attributes\{DataProvider, Test};
use PHPUnit\Framework\TestCase;

final class TicketPriorityTest extends TestCase
{
    /** @return iterable<string, array{TicketPriority, int}> */
    public static function slaCases(): iterable
    {
        yield 'низкий' => [TicketPriority::Low, 72];
        yield 'обычный' => [TicketPriority::Normal, 24];
        yield 'высокий' => [TicketPriority::High, 8];
        yield 'критический' => [TicketPriority::Critical, 2];
    }

    #[Test]
    #[DataProvider('slaCases')]
    public function срок_реакции_соответствует_приоритету(
        TicketPriority $priority,
        int $expectedHours,
    ): void {
        // фиксированная дата: тест не зависит от момента запуска
        $openedAt = new \DateTimeImmutable('2026-09-06 12:00:00');

        $deadline = $priority->slaDeadlineFrom($openedAt);

        self::assertSame(
            $expectedHours,
            (int) $openedAt->diff($deadline)->format('%h') + $openedAt->diff($deadline)->days * 24,
        );
    }

    #[Test]
    public function все_значения_имеют_срок_реакции(): void
    {
        // защита от забытой ветки при добавлении нового приоритета
        foreach (TicketPriority::cases() as $priority) {
            self::assertGreaterThan(0, $priority->responseHours(), $priority->value);
        }
    }
}
