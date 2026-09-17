<?php
// tests/Feature/Authorization/SanityTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('администратор проходит через before()', function (): void {
    $ticket = Ticket::factory()->closed()->create();
    $admin = User::factory()->admin()->create();

    foreach (['view', 'update', 'close', 'assign', 'delete', 'forceDelete'] as $ability) {
        expect($admin->can($ability, $ticket))->toBeTrue("admin не может «{$ability}»");
    }
});

it('гость не может ничего', function (): void {
    $ticket = Ticket::factory()->create();

    expect(\Illuminate\Support\Facades\Gate::forUser(null)->allows('view', $ticket))->toBeFalse();
});

it('отказ содержит понятную причину', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['subject' => 'Новая тема заявки'])
        ->assertForbidden()
        ->assertJsonPath('message', 'Закрытую заявку изменить нельзя.');
});
