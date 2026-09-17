<?php
// app/Exceptions/ApiExceptionRenderer.php
declare(strict_types=1);

namespace App\Exceptions;

use App\Enums\ErrorCode;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\ThrottleRequestsException;
use Throwable;

final readonly class ApiExceptionRenderer
{
    public function __invoke(Throwable $e, Request $request): JsonResponse
    {
        [$code, $message, $extra] = $this->resolve($e);
        $status = $code->httpStatus();

        if ($status >= 500) {
            logger()->error('api.server_error', [
                'exception' => $e::class,
                'message'   => $e->getMessage(),
                'where'     => $e->getFile() . ':' . $e->getLine(),
                'input'     => \App\Support\LogSanitizer::clean($request->all()),
            ]);
        }

        $body = [
            'message' => $message,
            'code'    => $code->value,
            ...$extra,
            'meta' => array_filter([
                'retryable'        => $code->isRetryable(),
                'requires_refresh' => $code->requiresRefresh() ?: null,
                'request_id'       => $request->header('X-Request-Id'),
            ], fn (mixed $v): bool => $v !== null),
        ];

        if ($status >= 500 && config('app.debug')) {
            $body['debug'] = ['exception' => $e::class, 'message' => $e->getMessage()];
        }

        return response()->json($body, $status);
    }

    /** @return array{ErrorCode, string, array<string, mixed>} */
    private function resolve(Throwable $e): array
    {
        return match (true) {
            $e instanceof ValidationException => [
                ErrorCode::ValidationFailed,
                'Данные не прошли проверку.',
                ['errors' => $e->errors()],
            ],
            $e instanceof AuthenticationException => [
                ErrorCode::Unauthenticated, 'Требуется авторизация.', [],
            ],
            // denyAsNotFound() в политике даёт 404: чужой объект не подтверждаем
            $e instanceof AuthorizationException => $e->response()?->status() === 404
                ? [ErrorCode::NotFound, 'Ресурс не найден.', []]
                : [ErrorCode::Forbidden, $e->getMessage() ?: 'Недостаточно прав.', []],
            $e instanceof ModelNotFoundException => [
                ErrorCode::NotFound, 'Ресурс не найден.', [],
            ],
            $e instanceof ThrottleRequestsException => [
                ErrorCode::TooManyRequests,
                'Слишком много запросов.',
                ['retry_after' => (int) ($e->getHeaders()['Retry-After'] ?? 60)],
            ],
            $e instanceof MethodNotAllowedHttpException => [
                ErrorCode::MethodNotAllowed, 'Метод не поддерживается.', [],
            ],
            $e instanceof NotFoundHttpException => [
                ErrorCode::NotFound, 'Ресурс не найден.', [],
            ],
            $e instanceof DomainException => [
                ErrorCode::from($e->errorCode()),
                $e->getMessage(),
                array_filter([...$e->context(), 'hint' => $e->hint()], fn ($v) => $v !== null),
            ],
            // abort()/abort_unless() и прочие HTTP-исключения фреймворка
            $e instanceof HttpExceptionInterface => match ($e->getStatusCode()) {
                400 => [ErrorCode::ValidationFailed, $e->getMessage() ?: 'Некорректный запрос.', []],
                403 => [ErrorCode::Forbidden, $e->getMessage() ?: 'Недостаточно прав.', []],
                404 => [ErrorCode::NotFound, 'Ресурс не найден.', []],
                405 => [ErrorCode::MethodNotAllowed, 'Метод не поддерживается.', []],
                409 => [ErrorCode::InvalidStatusTransition, $e->getMessage() ?: 'Конфликт состояния.', []],
                default => [ErrorCode::ServerError, 'Внутренняя ошибка сервера.', []],
            },
            default => [ErrorCode::ServerError, 'Внутренняя ошибка сервера.', []],
        };
    }
}
