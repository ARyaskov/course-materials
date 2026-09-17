<?php
// app/Http/Resources/CommentResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Comment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Comment */
final class CommentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'          => $this->id,
            'body'        => $this->body,
            'is_system'   => $this->is_system,
            'author'      => UserResource::make($this->whenLoaded('author')),
            'attachments' => AttachmentResource::collection($this->whenLoaded('attachments')),
            'created_at'  => $this->created_at->toIso8601String(),
        ];
    }
}
