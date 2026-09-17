<?php

declare(strict_types=1);

namespace App\Infrastructure\Mail;

use App\Domain\Ticket\Ticket;
use App\Domain\User\User;
use Symfony\Component\Mailer\Exception\TransportExceptionInterface;
use Symfony\Component\Mailer\MailerInterface as SymfonyMailer;
use Symfony\Component\Mime\Email;

final readonly class SmtpMailerAdapter implements MailerInterface
{
    public function __construct(
        private SymfonyMailer $mailer,
        private string $from,
        private string $baseUrl,
    ) {
    }

    public function sendAssigned(Ticket $ticket, User $assignee): void
    {
        $email = (new Email())
            ->from($this->from)
            ->to($assignee->email)
            ->subject(sprintf('Заявка #%d назначена на вас', $ticket->id->value))
            ->text(sprintf(
                "%s\n\nПриоритет: %s\nОткрыть: %s/tickets/%d\n",
                $ticket->title,
                $ticket->priority->value,
                $this->baseUrl,
                $ticket->id->value,
            ));

        try {
            $this->mailer->send($email);
        } catch (TransportExceptionInterface $e) {
            throw new MailDeliveryException($e->getMessage(), previous: $e);
        }
    }
}
