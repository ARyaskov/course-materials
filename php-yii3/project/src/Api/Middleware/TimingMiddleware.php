<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

final readonly class TimingMiddleware implements MiddlewareInterface
{
    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        // путь внутрь
        $startedAt = hrtime(true);

        $response = $handler->handle($request);

        // путь наружу
        $elapsedMs = (hrtime(true) - $startedAt) / 1_000_000;

        return $response->withHeader('X-Response-Time', sprintf('%.1fms', $elapsedMs));
    }
}
