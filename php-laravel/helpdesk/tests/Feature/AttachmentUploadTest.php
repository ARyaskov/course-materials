<?php
// tests/Feature/AttachmentUploadTest.php
declare(strict_types=1);

use App\Models\Attachment;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Http\Testing\File;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;

it('загружает изображение', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->image('Скриншот ошибки.png', 800, 600),
        ])
        ->assertCreated()
        ->assertJsonPath('data.original_name', 'Скриншот ошибки.png')
        ->assertJsonStructure(['data' => ['id', 'original_name', 'mime_type', 'size_bytes', 'url']]);

    expect(Attachment::query()->count())->toBe(1);
    Storage::disk('private')->assertExists(Attachment::query()->first()->path);
});

it('отклоняет исполняемый файл под видом изображения', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();

    $file = UploadedFile::fake()->createWithContent('photo.png', "<?php system(\$_GET['c']); ?>");

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", ['attachment' => $file])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['attachment']);

    expect(Attachment::query()->count())->toBe(0);
});

it('отклоняет слишком большой файл', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->create('big.pdf', 20 * 1024),   // 20 МБ при лимите 16
        ])
        ->assertStatus(422);
});

it('генерирует своё имя файла', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->image('../../../evil.png'),
        ])
        ->assertCreated();

    $attachment = Attachment::query()->first();

    expect($attachment->path)->not->toContain('..')
        ->and($attachment->path)->toMatch('#^tickets/\d{4}/\d{2}/\d+/[0-9a-f-]+\.png$#')
        ->and($attachment->original_name)->not->toContain('/');
});

it('не дублирует одинаковый файл', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();
    $file = UploadedFile::fake()->image('same.png');

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", ['attachment' => $file])
        ->assertCreated();

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->createWithContent(
                'other.png',
                $file->getContent(),
            ),
        ])
        ->assertCreated();

    expect(Attachment::query()->count())->toBe(1);
});

it('ограничивает число вложений на заявку', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();
    Attachment::factory()->count(10)->for($ticket, 'attachable')->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->image('one-more.png'),
        ])
        ->assertStatus(422);
});

it('не пускает постороннего', function (): void {
    Storage::fake('private');

    $ticket = Ticket::factory()->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->image('x.png'),
        ])
        ->assertForbidden();
});

it('ставит обработку в очередь', function (): void {
    Storage::fake('private');
    Queue::fake();

    $ticket = Ticket::factory()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", [
            'attachment' => UploadedFile::fake()->image('x.png'),
        ])->assertCreated();

    Queue::assertPushed(\App\Jobs\ProcessAttachment::class);
});
