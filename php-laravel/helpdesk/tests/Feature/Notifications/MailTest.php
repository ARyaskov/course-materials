<?php
// tests/Feature/Notifications/MailTest.php
declare(strict_types=1);

use App\Mail\TicketClosedMail;
use App\Models\Ticket;
use Illuminate\Support\Facades\Mail;

it('отправляет письмо автору', function (): void {
    Mail::fake();

    $ticket = Ticket::factory()->create(['status' => 'open']);

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    Mail::assertQueued(TicketClosedMail::class, fn (TicketClosedMail $mail): bool
        => $mail->hasTo($ticket->author->email) && $mail->ticket->id === $ticket->id);

    Mail::assertQueuedCount(1);
    Mail::assertNotQueued(\App\Mail\TicketCreatedMail::class);
});

it('не отправляет письмо неподтверждённому адресу', function (): void {
    Mail::fake();

    $ticket = Ticket::factory()->create();
    $ticket->author->update(['email_verified_at' => null]);

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    Mail::assertNothingQueued();
});
