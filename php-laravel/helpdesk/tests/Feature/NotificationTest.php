<?php
// tests/Feature/NotificationTest.php
declare(strict_types=1);

use App\Contracts\AgentDirectory;
use App\Contracts\Notifier;
use App\Models\Ticket;
use Tests\Doubles\FakeAgentDirectory;
use Tests\Doubles\FakeNotifier;

it('подменяет зависимость готовым объектом', function (): void {
    $fake = new FakeNotifier();
    $this->app->instance(Notifier::class, $fake);

    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    expect($fake->sent)->toHaveCount(1);
});

it('подменяет через mock', function (): void {
    $this->mock(Notifier::class)
        ->shouldReceive('send')
        ->once()
        ->withArgs(fn ($user, string $message): bool => str_contains($message, 'закрыта'));

    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();
});

it('подменяет только часть методов', function (): void {
    $this->partialMock(AgentDirectory::class, function ($mock): void {
        $mock->shouldReceive('find')->andReturn(null);
    });

    // остальные методы работают как обычно
});

it('перехватывает создание', function (): void {
    $this->spy(Notifier::class);

    $ticket = Ticket::factory()->create();
    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close");

    $this->app->make(Notifier::class)->shouldHaveReceived('send');
});
