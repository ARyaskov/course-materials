<?php
// tests/Feature/CloseStaleTicketsTest.php
declare(strict_types=1);

use App\Models\Ticket;

it('закрывает только устаревшие заявки', function (): void {
    Ticket::factory()->count(3)->create(['updated_at' => now()->subDays(40)]);
    Ticket::factory()->count(2)->create(['updated_at' => now()->subDay()]);

    $this->artisan('tickets:close-stale', ['--days' => 30])
        ->expectsConfirmation('Закрыть 3 заявок?', 'yes')
        ->expectsOutputToContain('Закрыто заявок: 3')
        ->assertSuccessful();

    expect(Ticket::query()->where('status', 'closed')->count())->toBe(3);
});

it('в режиме dry-run ничего не меняет', function (): void {
    Ticket::factory()->count(3)->create(['updated_at' => now()->subDays(40)]);

    $this->artisan('tickets:close-stale', ['--days' => 30, '--dry-run' => true])
        ->assertSuccessful();

    expect(Ticket::query()->where('status', 'closed')->count())->toBe(0);
});

it('отклоняет некорректный параметр', function (): void {
    $this->artisan('tickets:close-stale', ['--days' => 0])
        ->expectsOutputToContain('положительным')
        ->assertExitCode(2);
});
