<?php
// app/Exports/CsvExport.php
declare(strict_types=1);

namespace App\Exports;

use App\Contracts\ExportFormat;
use Illuminate\Support\Collection;

final readonly class CsvExport implements ExportFormat
{
    public function extension(): string
    {
        return 'csv';
    }

    public function mimeType(): string
    {
        return 'text/csv';
    }

    public function render(Collection $tickets): string
    {
        $out = fopen('php://temp', 'r+');
        fputcsv($out, ['id', 'subject', 'status', 'created_at']);

        foreach ($tickets as $ticket) {
            fputcsv($out, [
                $ticket->id,
                $ticket->subject,
                $ticket->status->value,
                $ticket->created_at->toDateString(),
            ]);
        }

        rewind($out);

        return (string) stream_get_contents($out);
    }
}
