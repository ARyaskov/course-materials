<?php
// app/Http/Resources/AttachmentResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Attachment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

/** @mixin Attachment */
final class AttachmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'            => $this->id,
            'original_name' => $this->original_name,
            'mime_type'     => $this->mime_type,
            'size_bytes'    => $this->size_bytes,
            'size_human'    => $this->humanSize(),
            'is_image'      => $this->isImage(),

            // подписанная ссылка для объектного хранилища, свой маршрут для локального
            'url' => $this->disk === 's3'
                ? Storage::disk('s3')->temporaryUrl($this->path, now()->addMinutes(15))
                : route('attachments.show', $this->resource),

            'uploaded_at' => $this->created_at->toIso8601String(),
        ];
    }
}
