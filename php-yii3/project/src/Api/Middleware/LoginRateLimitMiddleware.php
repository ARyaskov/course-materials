<?php

declare(strict_types=1);

namespace App\Api\Middleware;

/**
 * Собрано из фрагмента урока 15.3: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class LoginRateLimitMiddleware
{
    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $body = $request->getParsedBody();
        $email = is_array($body) && is_string($body['email'] ?? null)
            ? mb_strtolower(trim($body['email']))
            : '';

        $ip = (string) ($request->getAttribute('requestClientIp') ?? 'unknown');

        // ключ по IP — от перебора паролей одним источником
        $byIp = $this->limiter->check('login:ip:' . $ip, limit: 20);

        // ключ по ПАРЕ ip+email — от распределённого перебора одного аккаунта.
        // Именно пара, а не один email: иначе злоумышленник заблокирует
        // вход любому пользователю, зная только его адрес.
        $byPair = $this->limiter->check(
            'login:pair:' . hash('xxh128', $ip . '|' . $email),
            limit: 5,
        );

        if (!$byIp->allowed || !$byPair->allowed) {
            $decision = $byIp->allowed ? $byPair : $byIp;

            return $this->responder
                ->respond(ErrorResponse::of(ErrorType::RateLimited,
                    'Слишком много попыток входа. Повторите позже.'), $request)
                ->withHeader('Retry-After', (string) $decision->resetAfter);
        }

        return $handler->handle($request);
    }
}
