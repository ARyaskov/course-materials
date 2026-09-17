<?php

declare(strict_types=1);

namespace App\Infrastructure\Mail;

use App\Domain\Ticket\Ticket;
use App\Domain\User\User;

interface MailerInterface
{
    public function sendAssigned(Ticket $ticket, User $assignee): void;
}
