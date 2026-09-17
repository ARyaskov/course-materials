<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Psr\Http\Server\{MiddlewareInterface, RequestHandlerInterface};
use Psr\Log\LoggerInterface;
use Yiisoft\Db\Connection\ConnectionInterface;

final readonly class QueryCountMiddleware implements MiddlewareInterface
{
    public function __construct(
        private ConnectionInterface $db,
        private LoggerInterface $logger,
        private int $warnThreshold = 15,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $before = $this->db->getQueryCount();

        $response = $handler->handle($request);

        $count = $this->db->getQueryCount() - $before;

        if ($count > $this->warnThreshold) {
            // порог сработал — почти наверняка N+1
            $this->logger->warning('Подозрение на N+1', [
                'path' => $request->getUri()->getPath(),
                'queries' => $count,
            ]);
        }

        return $response->withHeader('X-Debug-Queries', (string) $count);
    }
}
