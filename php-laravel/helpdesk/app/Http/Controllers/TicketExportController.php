<?php
// app/Http/Controllers/TicketExportController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Contracts\ExportFormat;
use App\Exports\CsvExport;
use App\Exports\JsonExport;
use App\Models\Ticket;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class TicketExportController extends Controller
{
    private const array FORMATS = [
        'csv'  => CsvExport::class,
        'json' => JsonExport::class,
    ];

    public function __invoke(Request $request): Response
    {
        $key = $request->string('format', 'csv')->toString();

        abort_unless(isset(self::FORMATS[$key]), 422, 'Неподдерживаемый формат');

        /** @var ExportFormat $format */
        $format = app(self::FORMATS[$key]);

        $tickets = Ticket::query()->with('author')->limit(5000)->get();

        return response($format->render($tickets), 200, [
            'Content-Type'        => $format->mimeType(),
            'Content-Disposition' => "attachment; filename=tickets.{$format->extension()}",
        ]);
    }
}
