<?php

declare(strict_types=1);

namespace App\Tests\Functional\Infrastructure;

use App\Domain\Ticket\TicketRepositoryInterface;
use App\Infrastructure\Ticket\DbTicketRepository;
use App\Infrastructure\Ticket\TicketMapper;
use App\Tests\Contract\TicketRepositoryContractTest;
final class DbTicketRepositoryTest extends TicketRepositoryContractTest
{
    protected function createRepository(): TicketRepositoryInterface
    {
        $this->fixture->truncateAll();

        return new DbTicketRepository($this->connection(), new TicketMapper());
    }
}
