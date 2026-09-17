<?php

declare(strict_types=1);

namespace App\Infrastructure\Mail;

use App\Domain\Ticket\Ticket;
use App\Domain\User\User;

final readonly class FileMailer implements MailerInterface
{
    public function __construct(private string $directory)
    {
    }

    public function sendAssigned(Ticket $ticket, User $assignee): void
    {
        if (!is_dir($this->directory) && !mkdir($this->directory, 0o775, true)) {
            throw new MailDeliveryException("Не удалось создать {$this->directory}");
        }

        $file = sprintf('%s/%s-%d.eml', $this->directory, date('Ymd-His'), $ticket->id->value);

        file_put_contents($file, sprintf(
            "To: %s\nSubject: Заявка #%d назначена на вас\n\n%s\n",
            $assignee->email,
            $ticket->id->value,
            $ticket->title,
        ));
    }
}
