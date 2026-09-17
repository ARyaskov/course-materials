<?php
// tests/Feature/StorageTest.php
declare(strict_types=1);

use App\Models\Attachment;
use App\Models\Ticket;
use App\Models\User;
use App\Support\AttachmentPath;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

it('кладёт файл на приватный диск', function (): void {
    Storage::fake('private');

    $path = AttachmentPath::forTicket(119, 'png');
    Storage::disk('private')->put($path, 'содержимое');

    Storage::disk('private')->assertExists($path);
    expect($path)->toMatch('#^tickets/\d{4}/\d{2}/119/[0-9a-f-]+\.png$#');
});

it('не отдаёт приватный файл постороннему', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();
    $attachment = Attachment::factory()->for($ticket, 'attachable')->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->get(route('attachments.show', $attachment))
        ->assertNotFound();
});

it('отдаёт файл участнику заявки', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();
    $attachment = Attachment::factory()->for($ticket, 'attachable')->create([
        'path' => 'tickets/2026/09/1/test.txt',
        'original_name' => 'Отчёт.txt',
    ]);

    Storage::disk('private')->put($attachment->path, 'содержимое');

    $this->actingAs($ticket->author, 'sanctum')
        ->get(route('attachments.show', $attachment))
        ->assertOk()
        ->assertHeader('X-Content-Type-Options', 'nosniff')
        ->assertDownload('Отчёт.txt');
});

it('удаляет файл вместе с записью', function (): void {
    Storage::fake('private');

    $attachment = Attachment::factory()->create(['path' => 'tickets/2026/09/1/x.png']);
    Storage::disk('private')->put($attachment->path, 'x');

    $attachment->delete();

    Storage::disk('private')->assertMissing($attachment->path);
});

it('подписанная ссылка истекает', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();
    $attachment = Attachment::factory()->for($ticket, 'attachable')->create();
    Storage::disk('private')->put($attachment->path, 'x');

    $url = \Illuminate\Support\Facades\URL::temporarySignedRoute(
        'attachments.download', now()->addMinutes(5), ['attachment' => $attachment->id],
    );

    $this->get($url)->assertOk();

    $this->travel(10)->minutes();

    $this->get($url)->assertForbidden();
});

it('очистка не трогает свежие файлы', function (): void {
    Storage::fake('private');

    Storage::disk('private')->put('tickets/2026/09/1/orphan.txt', 'x');

    $this->artisan('files:prune', ['--dry-run' => true])
        ->expectsOutputToContain('Файлов без ссылок нет.')
        ->assertSuccessful();
});

it('поток не загружает файл в память', function (): void {
    Storage::fake('private');

    Storage::disk('private')->put('big.txt', str_repeat('a', 1_000_000));

    $before = memory_get_usage(true);
    $stream = Storage::disk('private')->readStream('big.txt');
    $after = memory_get_usage(true);

    fclose($stream);

    expect($after - $before)->toBeLessThan(500_000);
});
