<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\Db\Connection\ConnectionInterface;

final readonly class QueryProfilerMiddleware implements MiddlewareInterface
{
    public function __construct(private ConnectionInterface $db)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $startedAt = hrtime(true);

        $response = $handler->handle($request);

        $elapsedMs = (hrtime(true) - $startedAt) / 1_000_000;

        return $response
            ->withHeader('X-Debug-Time', sprintf('%.1fms', $elapsedMs))
            ->withHeader('X-Debug-Queries', (string) $this->db->getQueryCount());
    }
}
