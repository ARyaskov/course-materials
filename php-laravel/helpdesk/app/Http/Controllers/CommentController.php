<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Http\Resources\CommentResource;
use App\Models\Comment;
use App\Models\Ticket;
use App\Services\CommentWriter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;

final class CommentController extends Controller
{
    public function __construct(private readonly CommentWriter $comments)
    {
    }

    public function index(Ticket $ticket): AnonymousResourceCollection
    {
        $this->authorize('view', $ticket);

        return CommentResource::collection(
            $ticket->comments()
                ->with('author:id,name,role')
                ->oldest()
                ->paginate(30)
        );
    }

    public function store(Request $request, Ticket $ticket): JsonResponse
    {
        $this->authorize('view', $ticket);

        $data = $request->validate([
            'body' => ['required', 'string', 'min:2', 'max:5000'],
        ]);

        $comment = $this->comments->fromUser($ticket, $request->user(), $data['body']);

        return $this->created(
            CommentResource::make($comment->load('author:id,name,role')),
            route('tickets.comments.index', $ticket),
        );
    }

    public function destroy(Request $request, Comment $comment): Response
    {
        abort_unless(
            $comment->author_id === $request->user()->id || $request->user()->isAgent(),
            Response::HTTP_NOT_FOUND,
        );

        $comment->delete();

        return $this->noContent();
    }
}
