<?php
// app/Exceptions/TicketLimitExceededException.php
declare(strict_types=1);

namespace App\Exceptions;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

final class TicketLimitExceededException extends DomainException
{
    public function __construct(
        private readonly int $limit,
        private readonly int $current,
    ) {
        parent::__construct("Превышен лимит открытых заявок: {$current} из {$limit}");
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'ticket_limit_exceeded';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 422;
    }

    #[\Override]
    public function context(): array
    {
        return ['limit' => $this->limit, 'current' => $this->current];
    }

    /** Laravel вызовет этот метод сам, если он есть. */
    public function render(Request $request): ?JsonResponse
    {
        if (! $request->is('api/*')) {
            return null;
        }

        return response()->json([
            'message' => $this->getMessage(),
            'code'    => $this->errorCode(),
            ...$this->context(),
        ], $this->httpStatus());
    }

    /** И этот — вместо записи в общий лог. */
    public function report(): bool
    {
        logger()->info('ticket.limit_reached', $this->context());

        return true;   // true — дальше не сообщать
    }
}
