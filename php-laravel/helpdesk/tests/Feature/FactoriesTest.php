<?php
// tests/Feature/FactoriesTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;

it('каждая модель имеет фабрику', function (): void {
    $models = collect(glob(app_path('Models/*.php')))
        ->map(fn (string $f): string => 'App\\Models\\' . basename($f, '.php'));

    foreach ($models as $model) {
        $factory = 'Database\\Factories\\' . class_basename($model) . 'Factory';

        expect(class_exists($factory))->toBeTrue("Нет фабрики для {$model}");
    }
});

it('фабрика заявки создаёт корректную запись', function (): void {
    $ticket = Ticket::factory()->create();

    expect($ticket->exists)->toBeTrue()
        ->and($ticket->author)->toBeInstanceOf(User::class)
        ->and($ticket->uuid)->toHaveLength(36)
        ->and($ticket->sla_hours)->toBe($ticket->priority->responseHours());
});

it('состояние closed не нарушает ограничение схемы', function (): void {
    $tickets = Ticket::factory()->count(30)->closed()->create();

    foreach ($tickets as $ticket) {
        expect($ticket->resolved_at)->toBeGreaterThanOrEqual($ticket->created_at);
    }
});

it('recycle не создаёт лишних пользователей', function (): void {
    $user = User::factory()->create();

    Ticket::factory()->count(5)->recycle($user)->create();

    expect(User::query()->count())->toBe(1)
        ->and(Ticket::query()->where('author_id', $user->id)->count())->toBe(5);
});

it('состояние agent создаёт профиль', function (): void {
    $agent = User::factory()->agent()->create();

    expect($agent->agentProfile)->not->toBeNull()
        ->and($agent->agentProfile->max_tickets)->toBeGreaterThan(0);
});

it('автор подписан на свою заявку', function (): void {
    $ticket = Ticket::factory()->create();

    expect($ticket->subscribers->pluck('id'))->toContain($ticket->author_id);
});

it('внешние ключи проверяются', function (): void {
    expect(fn () => Comment::factory()->create(['ticket_id' => 999999]))
        ->toThrow(\Illuminate\Database\QueryException::class);
});
