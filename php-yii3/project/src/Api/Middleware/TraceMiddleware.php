<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Psr\Log\LoggerInterface;

final readonly class TraceMiddleware implements MiddlewareInterface
{
    public function __construct(
        private LoggerInterface $logger,
        private string $label,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $this->logger->debug("→ вход {$this->label}");

        $response = $handler->handle($request);

        $this->logger->debug("← выход {$this->label}", [
            'status' => $response->getStatusCode(),
        ]);

        return $response;
    }
}
