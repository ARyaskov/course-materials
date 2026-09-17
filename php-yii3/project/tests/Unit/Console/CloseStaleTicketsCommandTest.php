<?php

declare(strict_types=1);

namespace App\Tests\Unit\Console;

use App\Console\CloseStaleTicketsCommand;
use App\Domain\Ticket\TicketStatus;
use App\Tests\Support\{CollectingDispatcher, InMemoryTicketRepository};
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use Psr\Log\NullLogger;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Tester\CommandTester;

final class CloseStaleTicketsCommandTest extends TestCase
{
    #[Test]
    public function сухой_прогон_ничего_не_меняет(): void
    {
        $tickets = InMemoryTicketRepository::withStaleResolved(count: 3);

        $tester = new CommandTester($this->command($tickets));
        $tester->execute(['--days' => '14', '--dry-run' => true]);

        self::assertSame(Command::SUCCESS, $tester->getStatusCode());
        self::assertStringContainsString('Было бы закрыто заявок: 3', $tester->getDisplay());

        // ни одна заявка не изменила статус
        foreach ($tickets->all() as $ticket) {
            self::assertNotSame(TicketStatus::Closed, $ticket->status);
        }
    }

    #[Test]
    public function отрицательный_параметр_даёт_код_invalid(): void
    {
        $tester = new CommandTester($this->command(new InMemoryTicketRepository()));
        $tester->execute(['--days' => '-1']);

        self::assertSame(Command::INVALID, $tester->getStatusCode());
    }
}
