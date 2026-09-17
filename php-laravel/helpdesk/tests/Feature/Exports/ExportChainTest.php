<?php
// tests/Feature/Exports/ExportChainTest.php
declare(strict_types=1);

use Illuminate\Support\Facades\Bus;

it('запускает цепочку выгрузки', function (): void {
    Bus::fake();

    $this->actingAsAgent()->postJson('/api/v1/exports')->assertStatus(202);

    Bus::assertChained([
        \App\Jobs\PrepareExportData::class,
        \App\Jobs\BuildExportFile::class,
        \App\Jobs\NotifyExportReady::class,
    ]);
});

it('создаёт пачку по задаче на заявку', function (): void {
    Bus::fake();

    \App\Models\Ticket::factory()->count(25)->create();

    $this->artisan('tickets:reindex')->assertSuccessful();

    Bus::assertBatched(fn ($batch): bool => $batch->jobs->count() === 25);
});
