<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Api\Error\{ErrorResponder, ErrorResponse, ErrorType};
use App\Domain\Auth\TokenClaims;
use App\Domain\RateLimit\RateLimiterInterface;
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Psr\Http\Server\{MiddlewareInterface, RequestHandlerInterface};
use Psr\Log\LoggerInterface;

final readonly class RateLimitMiddleware implements MiddlewareInterface
{
    public function __construct(
        private RateLimiterInterface $limiter,
        private ErrorResponder $responder,
        private LoggerInterface $logger,
        private int $limit = 100,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $key = $this->resolveKey($request);
        $decision = $this->limiter->check($key, $this->limit);

        if (!$decision->allowed) {
            $this->logger->warning('Превышен лимит запросов', [
                'key' => $key,
                'path' => $request->getUri()->getPath(),
                'limit' => $decision->limit,
            ]);

            return $this->responder
                ->respond(ErrorResponse::of(ErrorType::RateLimited,
                    'Слишком много запросов. Повторите позже.'), $request)
                // клиент узнаёт, сколько ждать, из заголовка
                ->withHeader('Retry-After', (string) $decision->resetAfter)
                ->withHeader('X-RateLimit-Limit', (string) $decision->limit)
                ->withHeader('X-RateLimit-Remaining', '0')
                ->withHeader('X-RateLimit-Reset', (string) (time() + $decision->resetAfter));
        }

        // заголовки на успешных ответах тоже: клиент видит остаток и притормаживает сам
        return $handler->handle($request)
            ->withHeader('X-RateLimit-Limit', (string) $decision->limit)
            ->withHeader('X-RateLimit-Remaining', (string) $decision->remaining)
            ->withHeader('X-RateLimit-Reset', (string) (time() + $decision->resetAfter));
    }

    private function resolveKey(ServerRequestInterface $request): string
    {
        $claims = $request->getAttribute(AuthMiddleware::CLAIMS);

        // после аутентификации — по пользователю: офис за NAT не делит лимит
        if ($claims instanceof TokenClaims) {
            return 'user:' . $claims->userId;
        }

        // до аутентификации — по IP, восстановленному TrustedHostsNetworkResolver
        $ip = $request->getAttribute('requestClientIp');

        return 'ip:' . (is_string($ip) ? $ip : 'unknown');
    }
}
