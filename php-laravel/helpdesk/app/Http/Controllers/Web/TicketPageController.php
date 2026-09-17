<?php
// app/Http/Controllers/Web/TicketPageController.php
declare(strict_types=1);

namespace App\Http\Controllers\Web;

use App\Models\Ticket;
use Illuminate\View\View;

final class TicketPageController extends Controller
{
    public function index(): View
    {
        $tickets = Ticket::query()->with('author')->latest()->paginate(20);

        return view('tickets.index', ['tickets' => $tickets]);
    }
}
