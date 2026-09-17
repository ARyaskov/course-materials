<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Api\Event\{RequestFinished, RequestStarted};
use Psr\EventDispatcher\EventDispatcherInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

final readonly class RequestEventsMiddleware implements MiddlewareInterface
{
    public function __construct(private EventDispatcherInterface $events)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $this->events->dispatch(new RequestStarted($request));

        $startedAt = hrtime(true);
        $response = $handler->handle($request);

        $this->events->dispatch(new RequestFinished(
            request: $request,
            response: $response,
            durationMs: (hrtime(true) - $startedAt) / 1_000_000,
        ));

        return $response;
    }
}
