<?php
// app/Http/Resources/TicketResource.php — карточка
declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Ticket;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Ticket */
final class TicketResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $user = $request->user();

        return [
            // наружу отдаётся uuid — тот же ключ, по которому работает привязка маршрута
            'id' => $this->uuid,
            'number' => sprintf('HD-%06d', $this->id),
            'subject' => $this->subject,
            'body'    => $this->body,

            'status'   => ['value' => $this->status->value, 'label' => $this->status->label()],
            'priority' => ['value' => $this->priority->value, 'label' => $this->priority->label()],

            'author'      => UserResource::make($this->whenLoaded('author')),
            'assignee'    => UserResource::make($this->whenLoaded('assignee')),
            'tags'        => TagResource::collection($this->whenLoaded('tags')),
            'comments'    => CommentResource::collection($this->whenLoaded('comments')),
            'attachments' => AttachmentResource::collection($this->whenLoaded('attachments')),

            'sla' => [
                'hours'      => $this->sla_hours,
                'deadline'   => $this->slaDeadline()->toIso8601String(),
                'is_overdue' => $this->isOverdue(),
            ],

            'internal_note' => $this->when(
                $user?->isAgent() === true,
                fn (): ?string => $this->internal_note,
            ),

            'permissions' => [
                'can_close'   => $user?->can('close', $this->resource) ?? false,
                'can_assign'  => $user?->can('assign', $this->resource) ?? false,
                'can_comment' => $user?->can('comment', $this->resource) ?? false,
            ],

            'created_at'  => $this->created_at->toIso8601String(),
            'updated_at'  => $this->updated_at->toIso8601String(),
            'resolved_at' => $this->resolved_at?->toIso8601String(),
        ];
    }

    public function with(Request $request): array
    {
        return [
            'meta' => [
                'available_transitions' => array_map(
                    fn ($s): array => ['value' => $s->value, 'label' => $s->label()],
                    $this->status->allowedTransitions(),
                ),
            ],
        ];
    }
}
