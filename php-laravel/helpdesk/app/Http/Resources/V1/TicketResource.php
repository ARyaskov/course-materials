<?php
// app/Http/Resources/V1/TicketResource.php
declare(strict_types=1);

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

final class TicketResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'       => $this->id,
            'subject'  => $this->subject,
            'status'   => $this->status->value,          // плоская строка
            'author'   => $this->author->name,           // просто имя
            'created'  => $this->created_at->timestamp,  // unix-время
        ];
    }
}
