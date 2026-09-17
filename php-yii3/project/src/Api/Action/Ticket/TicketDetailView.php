<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Application\Ticket\TicketWithRelations;

final readonly class TicketDetailView
{
    /** @param list<CommentView> $comments */
    private function __construct(
        public int $id,
        public string $title,
        public string $description,
        public string $status,
        public string $priority,
        // связанные объекты в усечённом виде: имя есть, служебных полей нет
        public UserRefView $reporter,
        public ?UserRefView $assignee,
        public array $comments,
        public string $createdAt,
    ) {
    }

    public static function fromReadModel(TicketWithRelations $model): self
    {
        return new self(
            id: $model->ticket->id->value,
            title: $model->ticket->title,
            description: $model->ticket->description,
            status: $model->ticket->status->value,
            priority: $model->ticket->priority->value,
            reporter: UserRefView::fromEntity($model->reporter),
            assignee: $model->assignee === null
                ? null
                : UserRefView::fromEntity($model->assignee),
            comments: array_map(CommentView::fromEntity(...), $model->comments),
            createdAt: $model->ticket->createdAt->format(\DateTimeInterface::ATOM),
        );
    }
}
