<?php
// app/Http/Resources/TicketListResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Ticket;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Ticket */
final class TicketListResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            // наружу отдаётся uuid — тот же ключ, по которому работает привязка маршрута
            'id' => $this->uuid,
            'number' => sprintf('HD-%06d', $this->id),
            'subject' => $this->subject,

            'status'   => ['value' => $this->status->value, 'label' => $this->status->label()],
            'priority' => ['value' => $this->priority->value, 'label' => $this->priority->label()],

            'author'   => UserResource::make($this->whenLoaded('author')),
            'assignee' => UserResource::make($this->whenLoaded('assignee')),
            'tags'     => TagResource::collection($this->whenLoaded('tags')),

            'comments_count'      => $this->whenCounted('comments'),
            'agent_replies_count' => $this->whenCounted('agent_replies_count'),
            'has_attachments'     => $this->when(
                isset($this->attachments_exists),
                fn (): bool => (bool) $this->attachments_exists,
            ),

            'sla' => [
                'deadline'   => $this->slaDeadline()->toIso8601String(),
                'is_overdue' => $this->isOverdue(),
            ],

            'created_at' => $this->created_at->toIso8601String(),
        ];
    }
}
