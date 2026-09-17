<?php
// app/Http/Controllers/UploadUrlController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Http\Requests\RequestUploadUrlRequest;
use App\Support\AttachmentPath;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Storage;

final class UploadUrlController extends Controller
{
    public function __invoke(RequestUploadUrlRequest $request, \App\Models\Ticket $ticket): JsonResponse
    {
        $extension = $request->extension();
        $path = AttachmentPath::forTicket($ticket->id, $extension);

        $url = Storage::disk('s3')->temporaryUploadUrl(
            $path,
            now()->addMinutes(10),
        );

        return $this->ok([
            'upload_url' => $url['url'],
            'headers'    => $url['headers'],
            'path'       => $path,
            'expires_at' => now()->addMinutes(10)->toIso8601String(),
        ]);
    }
}
