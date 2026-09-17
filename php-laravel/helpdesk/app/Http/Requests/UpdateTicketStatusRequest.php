<?php
// app/Http/Requests/UpdateTicketStatusRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use App\Enums\TicketStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

final class UpdateTicketStatusRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            // только активные статусы, и только те, в которые можно перейти
            'status' => [
                'required',
                Rule::enum(TicketStatus::class)
                    ->only($this->route('ticket')->status->allowedTransitions()),
            ],
        ];
    }

    public function status(): TicketStatus
    {
        return $this->enum('status', TicketStatus::class);
    }
}
