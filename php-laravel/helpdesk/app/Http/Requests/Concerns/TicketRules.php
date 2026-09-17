<?php
// app/Http/Requests/Concerns/TicketRules.php
declare(strict_types=1);

namespace App\Http\Requests\Concerns;

use App\Enums\TicketPriority;
use App\Rules\NotProfane;
use Illuminate\Validation\Rule;

trait TicketRules
{
    /** @return array<string, list<mixed>> */
    protected function ticketRules(string $presence = 'required'): array
    {
        return [
            'subject'  => ['bail', $presence, 'string', 'min:5', 'max:200', new NotProfane()],
            'body'     => ['bail', $presence, 'string', 'min:10', 'max:10000'],
            'priority' => ['sometimes', Rule::enum(TicketPriority::class)],
            'tags'     => ['sometimes', 'array', 'max:5'],
            'tags.*'   => ['string', 'distinct', 'max:50'],
        ];
    }
}
