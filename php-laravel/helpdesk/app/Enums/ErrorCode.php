<?php
// app/Enums/ErrorCode.php
declare(strict_types=1);

namespace App\Enums;

enum ErrorCode: string
{
    case ValidationFailed = 'validation_failed';
    case Unauthenticated = 'unauthenticated';
    case Forbidden = 'forbidden';
    case NotFound = 'not_found';
    case EndpointNotFound = 'endpoint_not_found';
    case MethodNotAllowed = 'method_not_allowed';
    case TooManyRequests = 'too_many_requests';
    case ServiceUnavailable = 'service_unavailable';
    case ServerError = 'server_error';

    case TicketAlreadyClosed = 'ticket_already_closed';
    case TicketAlreadyAssigned = 'ticket_already_assigned';
    case TicketLimitExceeded = 'ticket_limit_exceeded';
    case InvalidStatusTransition = 'invalid_status_transition';
    case AgentOverloaded = 'agent_overloaded';
    case StaleData = 'stale_data';

    public function httpStatus(): int
    {
        return match ($this) {
            self::ValidationFailed, self::TicketLimitExceeded => 422,
            self::Unauthenticated                             => 401,
            self::Forbidden                                   => 403,
            self::NotFound, self::EndpointNotFound            => 404,
            self::MethodNotAllowed                            => 405,
            self::TicketAlreadyClosed,
            self::TicketAlreadyAssigned,
            self::InvalidStatusTransition,
            self::AgentOverloaded,
            self::StaleData                                   => 409,
            self::TooManyRequests                             => 429,
            self::ServiceUnavailable                          => 503,
            self::ServerError                                 => 500,
        };
    }

    /** Имеет ли смысл повторять тот же запрос. */
    public function isRetryable(): bool
    {
        return in_array($this, [
            self::TooManyRequests,
            self::ServiceUnavailable,
            self::ServerError,
        ], strict: true);
    }

    /** Нужно ли клиенту обновить свою копию данных. */
    public function requiresRefresh(): bool
    {
        return in_array($this, [
            self::StaleData,
            self::InvalidStatusTransition,
            self::TicketAlreadyClosed,
            self::TicketAlreadyAssigned,
        ], strict: true);
    }
}
