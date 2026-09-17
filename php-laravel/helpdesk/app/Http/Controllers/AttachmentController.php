<?php
// app/Http/Controllers/AttachmentController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Http\Requests\StoreAttachmentRequest;
use App\Http\Resources\AttachmentResource;
use App\Models\Ticket;
use App\Services\AttachmentService;
use Illuminate\Http\JsonResponse;

final class AttachmentController extends Controller
{
    public function __construct(private readonly AttachmentService $attachments)
    {
    }

    public function store(StoreAttachmentRequest $request, Ticket $ticket): JsonResponse
    {
        $attachment = $this->attachments->store(
            $ticket,
            $request->file('attachment'),
            $request->user(),
        );

        return $this->created(
            AttachmentResource::make($attachment),
            route('attachments.show', $attachment),
        );
    }
}
