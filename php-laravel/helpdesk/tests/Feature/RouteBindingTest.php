<?php
// tests/Feature/RouteBindingTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;

it('отдаёт 404 на несуществующую заявку', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets/999999')
        ->assertNotFound();
});

it('не пускает к комментарию чужой заявки', function (): void {
    $ticketA = Ticket::factory()->create();
    $ticketB = Ticket::factory()->create();
    $comment = Comment::factory()->for($ticketB)->create();

    // комментарий существует, но принадлежит другой заявке
    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticketA->id}/comments/{$comment->id}")
        ->assertNotFound();
});

it('обычный пользователь не видит чужую заявку', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertNotFound();   // не 403 — существование не раскрывается
});

it('находит удалённую заявку для восстановления', function (): void {
    $ticket = Ticket::factory()->create();
    $ticket->delete();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/restore")
        ->assertOk();

    expect($ticket->fresh()->trashed())->toBeFalse();
});

it('отсеивает нечисловой идентификатор без запроса к базе', function (): void {
    \DB::enableQueryLog();

    $this->actingAsAgent()->getJson('/api/v1/tickets/abc')->assertNotFound();

    expect(\DB::getQueryLog())->toBeEmpty();
});
