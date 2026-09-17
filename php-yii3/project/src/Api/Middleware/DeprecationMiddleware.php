<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Psr\Log\LoggerInterface;

final readonly class DeprecationMiddleware implements MiddlewareInterface
{
    public function __construct(
        private LoggerInterface $logger,
        private string $sunsetDate = '2027-03-01T00:00:00Z',
        private string $successorUri = 'https://api.helpdesk.example/api/v2',
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        // кто ещё ходит в старую версию — понадобится перед отключением
        $this->logger->info('Обращение к устаревшей версии API', [
            'path' => $request->getUri()->getPath(),
            'clientId' => $request->getAttribute('clientId'),
            'userAgent' => $request->getHeaderLine('User-Agent'),
        ]);

        $sunset = new \DateTimeImmutable($this->sunsetDate);

        return $handler->handle($request)
            ->withHeader('Deprecation', 'true')
            ->withHeader('Sunset', $sunset->format(\DateTimeInterface::RFC7231))
            ->withHeader('Link', sprintf('<%s>; rel="successor-version"', $this->successorUri));
    }
}
