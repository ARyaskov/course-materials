<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;

final readonly class JsonBodyParserMiddleware implements MiddlewareInterface
{
    private const MAX_DEPTH = 32;

    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
        private int $maxBodyBytes = 1_048_576,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        if (!$this->hasJsonBody($request)) {
            return $handler->handle($request);
        }

        $body = $request->getBody();

        // защита от огромного тела: проверяем ДО чтения в память
        if ($body->getSize() !== null && $body->getSize() > $this->maxBodyBytes) {
            return $this->error(
                'payload_too_large',
                sprintf('Тело запроса больше %d байт.', $this->maxBodyBytes),
                Status::PAYLOAD_TOO_LARGE,
            );
        }

        $raw = (string) $body;

        // пустое тело — это не ошибка разбора, а отсутствие данных
        if (trim($raw) === '') {
            return $handler->handle($request->withParsedBody(null));
        }

        try {
            $parsed = json_decode($raw, true, self::MAX_DEPTH, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            return $this->error('malformed_json', $e->getMessage(), Status::BAD_REQUEST);
        }

        // корневой скаляр или массив-список тоже разбирается, но контракту не отвечает
        if (!is_array($parsed)) {
            return $this->error(
                'malformed_body',
                'Тело запроса должно быть JSON-объектом.',
                Status::BAD_REQUEST,
            );
        }

        return $handler->handle($request->withParsedBody($parsed));
    }

    private function hasJsonBody(ServerRequestInterface $request): bool
    {
        // Content-Type приходит как "application/json; charset=utf-8" и в любом регистре
        $mime = strtolower(trim(explode(';', $request->getHeaderLine('Content-Type'))[0]));

        return $mime === 'application/json' || str_ends_with($mime, '+json');
    }

    private function error(string $type, string $message, int $status): ResponseInterface
    {
        return $this->responseFactory->createResponse(
            ['error' => ['type' => $type, 'message' => $message]],
            $status,
        );
    }
}
