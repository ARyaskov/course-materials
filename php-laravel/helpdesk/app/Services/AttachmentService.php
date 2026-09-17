<?php
// app/Services/AttachmentService.php
declare(strict_types=1);

namespace App\Services;

use App\Exceptions\AttachmentRejectedException;
use App\Models\Attachment;
use App\Models\Ticket;
use App\Models\User;
use App\Support\AttachmentPath;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

final readonly class AttachmentService
{
    /** тип содержимого → расширение, которое присвоим сами */
    private const array ALLOWED = [
        'image/png'       => 'png',
        'image/jpeg'      => 'jpg',
        'application/pdf' => 'pdf',
        'text/plain'      => 'txt',
        'text/csv'        => 'csv',
    ];

    public function store(Ticket $ticket, UploadedFile $file, User $uploader): Attachment
    {
        $this->assertValid($file);

        $mime = $file->getMimeType();
        $extension = self::ALLOWED[$mime];
        $path = AttachmentPath::forTicket($ticket->id, $extension);
        $disk = config('helpdesk.attachments.disk');

        $checksum = hash_file('sha256', $file->getRealPath());

        // тот же файл уже приложен — не дублируем в хранилище
        $existing = $ticket->attachments()->where('checksum', $checksum)->first();

        if ($existing !== null) {
            return $existing;
        }

        // сначала файл, потом запись: запись без файла хуже файла без записи
        $file->storeAs(dirname($path), basename($path), ['disk' => $disk]);

        try {
            return DB::transaction(fn (): Attachment => $ticket->attachments()->create([
                'uploaded_by'   => $uploader->id,
                'disk'          => $disk,
                'path'          => $path,
                'original_name' => $this->safeName($file->getClientOriginalName()),
                'mime_type'     => $mime,
                'size_bytes'    => $file->getSize(),
                'checksum'      => $checksum,
            ]));
        } catch (\Throwable $e) {
            Storage::disk($disk)->delete($path);   // не оставляем файл-сироту

            throw $e;
        }
    }

    private function assertValid(UploadedFile $file): void
    {
        if (! $file->isValid()) {
            throw new AttachmentRejectedException('Файл не был загружен полностью.');
        }

        $mime = $file->getMimeType();

        if (! isset(self::ALLOWED[$mime])) {
            throw new AttachmentRejectedException("Тип файла «{$mime}» не поддерживается.");
        }

        $maxBytes = config('helpdesk.attachments.max_size_mb') * 1024 * 1024;

        if ($file->getSize() > $maxBytes) {
            throw new AttachmentRejectedException('Файл превышает допустимый размер.');
        }
    }

    /** Имя показываем пользователю — вычищаем всё опасное. */
    private function safeName(string $name): string
    {
        $name = basename($name);                                   // убираем пути
        $name = preg_replace('/[\x00-\x1F\x7F]/u', '', $name) ?? '';  // управляющие символы
        $name = str_replace(['"', '\\', "\r", "\n"], '', $name);   // ломающие заголовок

        return \Illuminate\Support\Str::limit($name, 200, '');
    }
}
