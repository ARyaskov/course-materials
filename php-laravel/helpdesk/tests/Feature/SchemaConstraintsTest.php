<?php
// tests/Feature/SchemaConstraintsTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

it('не даёт записать неизвестный статус', function (): void {
    expect(fn () => DB::table('tickets')->insert([
        'author_id'  => User::factory()->create()->id,
        'subject'    => 'Тест',
        'body'       => 'Текст',
        'status'     => 'archived',
        'priority'   => 'normal',
        'uuid'       => \Str::uuid7(),
        'created_at' => now(),
        'updated_at' => now(),
    ]))->toThrow(QueryException::class);
});

it('не даёт подписать пользователя дважды', function (): void {
    $ticket = Ticket::factory()->create();
    $user = User::factory()->create();

    $ticket->subscribers()->attach($user->id);

    expect(fn () => $ticket->subscribers()->attach($user->id))
        ->toThrow(\Illuminate\Database\UniqueConstraintViolationException::class);
});

it('не даёт закрыть заявку раньше создания', function (): void {
    $ticket = Ticket::factory()->create();

    expect(fn () => DB::table('tickets')
        ->where('id', $ticket->id)
        ->update(['resolved_at' => $ticket->created_at->subDay()]))
        ->toThrow(QueryException::class);
});

it('использует индекс для списка по статусу', function (): void {
    Ticket::factory()->count(50)->create();

    $sql = Ticket::query()->where('status', 'open')->orderByDesc('created_at')->limit(20)->toRawSql();
    $plan = implode(' ', array_column(DB::select("EXPLAIN {$sql}"), 'QUERY PLAN'));

    expect($plan)->toContain('Index Scan');
})->skip(fn () => DB::connection()->getDriverName() !== 'pgsql');
