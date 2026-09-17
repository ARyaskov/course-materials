<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure;

use App\Domain\Ticket\TicketRepositoryInterface;
use App\Tests\Contract\TicketRepositoryContractTest;
use App\Tests\Support\InMemoryTicketRepository;

final class InMemoryTicketRepositoryTest extends TicketRepositoryContractTest
{
    protected function createRepository(): TicketRepositoryInterface
    {
        return new InMemoryTicketRepository();
    }
}
