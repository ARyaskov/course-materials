<?php
// app/Services/CommentWriter.php
declare(strict_types=1);

namespace App\Services;

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;

final readonly class CommentWriter
{
    public function system(Ticket $ticket, User $actor, string $body): Comment
    {
        return $ticket->comments()->create([
            'author_id' => $actor->id,
            'is_system' => true,
            'body'      => $body,
        ]);
    }

    public function fromUser(Ticket $ticket, User $author, string $body): Comment
    {
        return $ticket->comments()->create([
            'author_id' => $author->id,
            'is_system' => false,
            'body'      => $body,
        ]);
    }
}
