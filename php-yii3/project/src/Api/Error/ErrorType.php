<?php

declare(strict_types=1);

namespace App\Api\Error;

use Yiisoft\Http\Status;

enum ErrorType: string
{
    // 400 — запрос невозможно понять
    case MalformedBody = 'malformed_body';
    case MalformedJson = 'malformed_json';

    // 401 / 403 — вопросы доступа
    case Unauthorized = 'unauthorized';
    case TokenExpired = 'token_expired';
    case AccessDenied = 'access_denied';

    // 404 — ресурса нет
    case NotFound = 'not_found';
    case TicketNotFound = 'ticket_not_found';
    case UserNotFound = 'user_not_found';

    // 409 — конфликт с текущим состоянием
    case IllegalTransition = 'illegal_transition';
    case AssigneeOverloaded = 'assignee_overloaded';
    case EmailAlreadyTaken = 'email_already_taken';

    // 422 — понято, но не годится
    case ValidationFailed = 'validation_failed';

    // 429 / 5xx
    case RateLimited = 'rate_limited';
    case InternalError = 'internal_error';
    case ServiceUnavailable = 'service_unavailable';

    public function status(): int
    {
        return match ($this) {
            self::MalformedBody, self::MalformedJson => Status::BAD_REQUEST,
            self::Unauthorized, self::TokenExpired => Status::UNAUTHORIZED,
            self::AccessDenied => Status::FORBIDDEN,
            self::NotFound, self::TicketNotFound, self::UserNotFound => Status::NOT_FOUND,
            self::IllegalTransition, self::AssigneeOverloaded,
            self::EmailAlreadyTaken => Status::CONFLICT,
            self::ValidationFailed => Status::UNPROCESSABLE_ENTITY,
            self::RateLimited => Status::TOO_MANY_REQUESTS,
            self::ServiceUnavailable => Status::SERVICE_UNAVAILABLE,
            self::InternalError => Status::INTERNAL_SERVER_ERROR,
        };
    }

    /** Стоит ли клиенту повторять запрос — ответ на самый частый вопрос клиента. */
    public function isRetryable(): bool
    {
        return match ($this) {
            self::RateLimited, self::ServiceUnavailable, self::InternalError => true,
            default => false,
        };
    }
}
