<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Ticket;

use App\Domain\Ticket\TicketId;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class TicketIdTest extends TestCase
{
    #[Test]
    public function отвергает_отрицательное_значение(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        TicketId::fromInt(-1);
    }

    #[Test]
    public function новый_идентификатор_помечен_как_новый(): void
    {
        self::assertTrue(TicketId::next()->isNew());
        self::assertFalse(TicketId::fromInt(42)->isNew());
    }

    #[Test]
    public function равенство_по_значению_а_не_по_ссылке(): void
    {
        // два разных объекта с одним значением равны
        self::assertTrue(TicketId::fromInt(42)->equals(TicketId::fromInt(42)));
        self::assertFalse(TicketId::fromInt(42)->equals(TicketId::fromInt(43)));
    }
}
