<?php
// app/Http/Controllers/Api/V2/TicketController.php
declare(strict_types=1);

namespace App\Http\Controllers\Api\V2;

use App\Http\Resources\V2\TicketResource;
use App\Http\Controllers\Api\V1\TicketController as V1Controller;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

final class TicketController extends V1Controller
{
    #[\Override]
    public function index(Request $request): AnonymousResourceCollection
    {
        return TicketResource::collection($this->query($request)->paginate());
    }
}
