<?php
// tests/Feature/MigrationsTest.php
declare(strict_types=1);

use Illuminate\Support\Facades\Schema;

it('создаёт таблицу заявок со всеми колонками', function (): void {
    expect(Schema::hasTable('tickets'))->toBeTrue();

    expect(Schema::hasColumns('tickets', [
        'id', 'author_id', 'assignee_id', 'subject', 'body',
        'status', 'priority', 'resolved_at', 'created_at', 'deleted_at',
    ]))->toBeTrue();
});

it('внешний ключ автора удаляет заявки каскадом', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(3)->for($user, 'author')->create();

    $user->forceDelete();

    expect(Ticket::withTrashed()->count())->toBe(0);
});

it('исполнитель обнуляется при удалении пользователя', function (): void {
    $agent = User::factory()->agent()->create();
    $ticket = Ticket::factory()->create(['assignee_id' => $agent->id]);

    $agent->forceDelete();

    expect($ticket->fresh()->assignee_id)->toBeNull();
});

it('миграции откатываются', function (): void {
    $this->artisan('migrate:rollback')->assertSuccessful();
    $this->artisan('migrate')->assertSuccessful();
});
