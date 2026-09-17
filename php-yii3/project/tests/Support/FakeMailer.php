<?php

declare(strict_types=1);

namespace App\Tests\Support;

use App\Domain\Ticket\Ticket;
use App\Domain\User\User;
use App\Infrastructure\Mail\MailerInterface;

/**
 * Заглушка с состоянием: собирает отправленное, чтобы тест мог это проверить.
 * Такой объект понятнее мока — видно, что именно он делает.
 */
final class FakeMailer implements MailerInterface
{
    /** @var list<array{ticket: Ticket, assignee: User}> */
    private array $sent = [];

    private ?\Throwable $failure = null;

    public function sendAssigned(Ticket $ticket, User $assignee): void
    {
        if ($this->failure !== null) {
            throw $this->failure;
        }

        $this->sent[] = ['ticket' => $ticket, 'assignee' => $assignee];
    }

    public function failWith(\Throwable $e): void
    {
        $this->failure = $e;
    }

    /** @return list<array{ticket: Ticket, assignee: User}> */
    public function sent(): array
    {
        return $this->sent;
    }

    public function sentCount(): int
    {
        return count($this->sent);
    }
}
