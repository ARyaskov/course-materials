<?php

declare(strict_types=1);

namespace App\Observers;

use App\Models\Comment;

final class CommentObserver
{
    public function created(Comment $comment): void
    {
        // ответ сотрудника снимает признак «без ответа» и обновляет активность заявки
        $comment->ticket?->touch();
    }

    public function deleted(Comment $comment): void
    {
        $comment->ticket?->touch();
    }
}
