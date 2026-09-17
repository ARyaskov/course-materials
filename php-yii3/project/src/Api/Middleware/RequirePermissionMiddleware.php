<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Api\Error\{ErrorResponder, ErrorResponse, ErrorType};
use App\Domain\Auth\TokenClaims;
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Psr\Http\Server\{MiddlewareInterface, RequestHandlerInterface};
use Psr\Log\LoggerInterface;

final readonly class RequirePermissionMiddleware implements MiddlewareInterface
{
    public function __construct(
        private string $permission,
        private ErrorResponder $responder,
        private LoggerInterface $logger,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        /** @var TokenClaims|null $claims */
        $claims = $request->getAttribute(AuthMiddleware::CLAIMS);

        if ($claims === null) {
            // middleware стоит вне защищённой группы — ошибка конфигурации
            throw new \LogicException(
                RequirePermissionMiddleware::class . ' требует AuthMiddleware выше по цепочке.',
            );
        }

        if (!in_array($this->permission, $claims->permissions, true)) {
            // отказ в доступе логируется: это событие безопасности
            $this->logger->warning('Отказано в доступе', [
                'userId' => $claims->userId,
                'role' => $claims->role->value,
                'required' => $this->permission,
                'path' => $request->getUri()->getPath(),
            ]);

            return $this->responder->respond(
                // сообщение не раскрывает, существует ли ресурс
                ErrorResponse::of(ErrorType::AccessDenied, 'Недостаточно прав.'),
                $request,
            );
        }

        return $handler->handle($request);
    }
}
