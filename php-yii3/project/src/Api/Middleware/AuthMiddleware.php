<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Api\Error\{ErrorResponder, ErrorResponse, ErrorType};
use App\Domain\Auth\{AccessTokenServiceInterface, TokenClaims};
use App\Domain\Auth\Exception\{InvalidTokenException, TokenExpiredException};
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Psr\Http\Server\{MiddlewareInterface, RequestHandlerInterface};
use Psr\Log\LoggerInterface;

final readonly class AuthMiddleware implements MiddlewareInterface
{
    public const CLAIMS = 'authClaims';
    public const USER_ID = 'userId';

    public function __construct(
        private AccessTokenServiceInterface $tokens,
        private ErrorResponder $responder,
        private LoggerInterface $logger,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $token = $this->extractToken($request);

        if ($token === null) {
            return $this->unauthorized($request, ErrorType::Unauthorized,
                'Требуется заголовок Authorization: Bearer <token>.');
        }

        try {
            $claims = $this->tokens->validate($token);
        } catch (TokenExpiredException $e) {
            // отдельный тип: клиент поймёт, что нужно обновить токен,
            // а не показывать форму входа
            return $this->unauthorized($request, ErrorType::TokenExpired,
                'Срок действия токена истёк.');
        } catch (InvalidTokenException $e) {
            $this->logger->warning('Отклонён невалидный токен', [
                'reason' => $e->getMessage(),
                'clientIp' => $request->getAttribute('requestClientIp'),
            ]);

            return $this->unauthorized($request, ErrorType::Unauthorized,
                'Токен недействителен.');
        }

        // обогащаем запрос — результат обязательно передаём дальше
        return $handler->handle(
            $request
                ->withAttribute(self::CLAIMS, $claims)
                ->withAttribute(self::USER_ID, $claims->userId),
        );
    }

    private function extractToken(ServerRequestInterface $request): ?string
    {
        $header = $request->getHeaderLine('Authorization');

        // регистр схемы не фиксирован спецификацией: bearer и Bearer равнозначны
        if (preg_match('/^Bearer\s+(\S+)$/i', $header, $matches) !== 1) {
            return null;
        }

        return $matches[1];
    }

    private function unauthorized(
        ServerRequestInterface $request,
        ErrorType $type,
        string $message,
    ): ResponseInterface {
        return $this->responder
            ->respond(ErrorResponse::of($type, $message), $request)
            ->withHeader('WWW-Authenticate', 'Bearer realm="helpdesk"');
    }
}
