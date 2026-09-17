<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Domain\Ticket\Exception\{IllegalTransitionException, TicketNotFoundException};
use App\Domain\Shared\Exception\AccessDeniedException;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;

final readonly class DomainExceptionMiddleware implements MiddlewareInterface
{
    private const MAP = [
        TicketNotFoundException::class => [Status::NOT_FOUND, 'not_found'],
        IllegalTransitionException::class => [Status::CONFLICT, 'illegal_transition'],
        AccessDeniedException::class => [Status::FORBIDDEN, 'access_denied'],
    ];

    public function __construct(private DataResponseFactoryInterface $responseFactory)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        try {
            return $handler->handle($request);
        } catch (\DomainException $e) {
            [$status, $type] = self::MAP[$e::class] ?? [Status::BAD_REQUEST, 'domain_error'];

            return $this->responseFactory->createResponse(
                ['error' => ['type' => $type, 'message' => $e->getMessage()]],
                $status,
            );
        }
    }
}
