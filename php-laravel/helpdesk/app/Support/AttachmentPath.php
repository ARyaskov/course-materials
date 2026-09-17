<?php
// app/Support/AttachmentPath.php
declare(strict_types=1);

namespace App\Support;

use Illuminate\Support\Str;

final readonly class AttachmentPath
{
    /** tickets/2026/09/119/0193f2c1-8a44-7c3e.png */
    public static function forTicket(int $ticketId, string $extension): string
    {
        return sprintf(
            'tickets/%s/%d/%s.%s',
            now()->format('Y/m'),
            $ticketId,
            Str::uuid7(),
            $extension,
        );
    }

    /** exports/2026/09/07/0193f2c1-8a44-7c3e.csv */
    public static function forExport(string $exportId): string
    {
        return sprintf('exports/%s/%s.csv', now()->format('Y/m/d'), $exportId);
    }
}
