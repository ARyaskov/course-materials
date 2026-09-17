<?php
// app/Exports/JsonExport.php
declare(strict_types=1);

namespace App\Exports;

use App\Contracts\ExportFormat;
use Illuminate\Support\Collection;

final readonly class JsonExport implements ExportFormat
{
    public function extension(): string
    {
        return 'json';
    }

    public function mimeType(): string
    {
        return 'application/json';
    }

    public function render(Collection $tickets): string
    {
        return $tickets
            ->map(fn ($t) => ['id' => $t->id, 'subject' => $t->subject, 'status' => $t->status->value])
            ->toJson(JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    }
}
