<?php
// app/Observers/AttachmentObserver.php
declare(strict_types=1);

namespace App\Observers;

use App\Models\Attachment;

final class AttachmentObserver
{
    public function deleted(Attachment $attachment): void
    {
        // файл удаляем вместе с записью
        $attachment->deleteFile();
    }
}
