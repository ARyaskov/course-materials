<?php
// app/Jobs/ProcessAttachment.php
declare(strict_types=1);

namespace App\Jobs;

use App\Models\Attachment;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Storage;

final class ProcessAttachment implements ShouldQueue
{
    use Queueable;

    public int $tries = 2;

    public int $timeout = 120;

    public function __construct(public readonly int $attachmentId)
    {
    }

    public function handle(): void
    {
        $attachment = Attachment::query()->find($this->attachmentId);

        if ($attachment === null || ! $attachment->exists()) {
            return;
        }

        if ($attachment->isImage()) {
            $this->makeThumbnail($attachment);
        }

        $attachment->update(['processed_at' => now()]);
    }

    private function makeThumbnail(Attachment $attachment): void
    {
        $source = Storage::disk($attachment->disk)->path($attachment->path);

        $image = match ($attachment->mime_type) {
            'image/png'  => imagecreatefrompng($source),
            'image/jpeg' => imagecreatefromjpeg($source),
            default      => null,
        };

        if ($image === false || $image === null) {
            return;
        }

        $thumb = imagescale($image, 320);
        $thumbPath = preg_replace('/(\.\w+)$/', '_thumb$1', $attachment->path);

        ob_start();
        imagepng($thumb);
        Storage::disk($attachment->disk)->put($thumbPath, (string) ob_get_clean());

        imagedestroy($image);
        imagedestroy($thumb);

        $attachment->update(['thumbnail_path' => $thumbPath]);
    }
}
