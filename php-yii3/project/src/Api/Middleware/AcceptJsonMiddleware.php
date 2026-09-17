<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;

final readonly class AcceptJsonMiddleware implements MiddlewareInterface
{
    public function __construct(private DataResponseFactoryInterface $responseFactory)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $accept = $request->getHeaderLine('Accept');

        // отсутствие заголовка означает «подойдёт что угодно»
        if ($accept === '' || $this->acceptsJson($accept)) {
            return $handler->handle($request);
        }

        return $this->responseFactory->createResponse(
            ['error' => [
                'type' => 'not_acceptable',
                'message' => 'API отдаёт только application/json.',
            ]],
            Status::NOT_ACCEPTABLE,
        );
    }

    private function acceptsJson(string $accept): bool
    {
        foreach (explode(',', $accept) as $part) {
            // отбрасываем q-фактор: "application/json;q=0.9"
            $mime = strtolower(trim(explode(';', $part)[0]));

            if (in_array($mime, ['application/json', 'application/*', '*/*'], true)
                || str_ends_with($mime, '+json')
            ) {
                return true;
            }
        }

        return false;
    }
}
