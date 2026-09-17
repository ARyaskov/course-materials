<?php
// tests/Feature/JobsTest.php
declare(strict_types=1);

use App\Jobs\GenerateTicketExport;
use App\Jobs\NotifyTicketClosed;
use App\Models\Export;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;

it('ставит задачу в нужную очередь', function (): void {
    Queue::fake();

    $this->actingAsAgent()->postJson('/api/v1/exports')->assertStatus(202);

    Queue::assertPushedOn('exports', GenerateTicketExport::class);
});

it('выполняет экспорт и сохраняет файл', function (): void {
    Storage::fake('private');

    $user = User::factory()->agent()->create();
    Ticket::factory()->count(5)->create();
    $export = Export::factory()->create(['user_id' => $user->id, 'status' => 'queued']);

    new GenerateTicketExport($export->id, $user->id)->handle();

    expect($export->fresh()->status)->toBe('done');
    Storage::disk('private')->assertExists("exports/{$export->id}.csv");
});

it('помечает экспорт упавшим при сбое', function (): void {
    $export = Export::factory()->create(['status' => 'processing']);

    new GenerateTicketExport($export->id, 1)->failed(new \RuntimeException('сбой'));

    expect($export->fresh()->status)->toBe('failed')
        ->and($export->fresh()->error)->toContain('сбой');
});

it('цепочка выполняет задачи по порядку', function (): void {
    Bus::fake();

    $this->actingAsAgent()->postJson('/api/v1/exports')->assertStatus(202);

    Bus::assertChained([
        \App\Jobs\PrepareExportData::class,
        \App\Jobs\BuildExportFile::class,
        \App\Jobs\NotifyExportReady::class,
    ]);
});

it('пачка содержит задачу на каждую заявку', function (): void {
    Bus::fake();

    Ticket::factory()->count(10)->create();

    $this->actingAsAgent()->postJson('/api/v1/maintenance/reindex')->assertStatus(202);

    Bus::assertBatched(fn (\Illuminate\Bus\PendingBatch $batch): bool
        => $batch->name === 'Переиндексация заявок' && $batch->jobs->count() === 10);
});

it('не выполняет две задачи для одной заявки одновременно', function (): void {
    $job = new NotifyTicketClosed(119);

    $middleware = collect($job->middleware())
        ->first(fn (object $m): bool => $m instanceof \Illuminate\Queue\Middleware\WithoutOverlapping);

    expect($middleware)->not->toBeNull();
});
