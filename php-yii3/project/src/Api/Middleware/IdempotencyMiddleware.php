<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Psr\SimpleCache\CacheInterface;

final readonly class IdempotencyMiddleware implements MiddlewareInterface
{
    public function __construct(private CacheInterface $cache)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $key = $request->getHeaderLine('Idempotency-Key');

        if ($key === '' || !in_array($request->getMethod(), ['POST', 'PATCH'], true)) {
            return $handler->handle($request);
        }

        $cacheKey = 'idempotency:' . hash('xxh128', $key);

        /** @var array{status:int, body:string}|null $stored */
        $stored = $this->cache->get($cacheKey);

        if ($stored !== null) {
            // повтор: отдаём тот же результат, ничего не создавая
            $response = $handler->handle($request->withAttribute('replayed', true));

            return $response->withStatus($stored['status'])
                ->withHeader('Idempotent-Replay', 'true');
        }

        $response = $handler->handle($request);

        if ($response->getStatusCode() < 400) {
            $this->cache->set($cacheKey, [
                'status' => $response->getStatusCode(),
                'body' => (string) $response->getBody(),
            ], 86400);
        }

        return $response;
    }
}
