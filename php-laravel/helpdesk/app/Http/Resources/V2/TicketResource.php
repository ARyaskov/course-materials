<?php
// app/Http/Resources/V2/TicketResource.php
declare(strict_types=1);

namespace App\Http\Resources\V2;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

final class TicketResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'      => $this->id,
            'subject' => $this->subject,
            'status'  => [
                'value' => $this->status->value,
                'label' => $this->status->label(),
            ],
            'author'  => UserResource::make($this->whenLoaded('author')),
            'created_at' => $this->created_at->toIso8601String(),   // ISO вместо unix
        ];
    }
}
