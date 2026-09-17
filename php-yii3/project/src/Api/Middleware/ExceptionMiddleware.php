<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Domain\Shared\Exception\{AccessDeniedException, DomainException};
use App\Domain\Ticket\Exception\{IllegalTransitionException, TicketNotFoundException};
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Psr\Log\LoggerInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;

final readonly class ExceptionMiddleware implements MiddlewareInterface
{
    /** @var array<class-string<DomainException>, int> */
    private const STATUS_MAP = [
        TicketNotFoundException::class => Status::NOT_FOUND,
        IllegalTransitionException::class => Status::CONFLICT,
        AccessDeniedException::class => Status::FORBIDDEN,
    ];

    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
        private LoggerInterface $logger,
        private bool $debug = false,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        try {
            return $handler->handle($request);
        } catch (DomainException $e) {
            return $this->domainError($e);
        } catch (\Throwable $e) {
            return $this->serverError($e, $request);
        }
    }

    private function domainError(DomainException $e): ResponseInterface
    {
        $status = self::STATUS_MAP[$e::class] ?? Status::BAD_REQUEST;

        // ожидаемая ошибка — не повод для error-уровня
        $this->logger->info('Доменная ошибка', [
            'exception' => $e::class,
            'type' => $e->errorType(),
        ]);

        return $this->responseFactory->createResponse(
            ['error' => ['type' => $e->errorType(), 'message' => $e->getMessage()]],
            $status,
        );
    }

    private function serverError(\Throwable $e, ServerRequestInterface $request): ResponseInterface
    {
        // подробности — в лог, где им и место
        $this->logger->error('Непредвиденная ошибка', [
            'exception' => $e::class,
            'message' => $e->getMessage(),
            'file' => $e->getFile(),
            'line' => $e->getLine(),
            'path' => $request->getUri()->getPath(),
            'previous' => $this->rootCause($e),
        ]);

        $body = ['error' => [
            'type' => 'internal_error',
            'message' => 'Внутренняя ошибка сервера.',
        ]];

        // подробности наружу — только в разработке
        if ($this->debug) {
            $body['error']['debug'] = [
                'exception' => $e::class,
                'message' => $e->getMessage(),
                'file' => sprintf('%s:%d', $e->getFile(), $e->getLine()),
                'trace' => array_slice(explode("\n", $e->getTraceAsString()), 0, 15),
            ];
        }

        return $this->responseFactory->createResponse($body, Status::INTERNAL_SERVER_ERROR);
    }

    /** Первопричина: PDOException важнее обёртки RepositoryException. */
    private function rootCause(\Throwable $e): ?string
    {
        $previous = $e;

        while ($previous->getPrevious() !== null) {
            $previous = $previous->getPrevious();
        }

        return $previous === $e
            ? null
            : sprintf('%s: %s', $previous::class, $previous->getMessage());
    }
}
