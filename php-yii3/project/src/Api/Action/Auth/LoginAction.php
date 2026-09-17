<?php

declare(strict_types=1);

namespace App\Api\Action\Auth;

use App\Application\Auth\{AuthenticateUserService, IssueTokenPairService, LoginInput};
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Yiisoft\DataResponse\DataResponseFactoryInterface;

final readonly class LoginAction
{
    public function __construct(
        private AuthenticateUserService $auth,
        private IssueTokenPairService $tokens,
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(ServerRequestInterface $request): ResponseInterface
    {
        /** @var LoginInput $input */
        $input = $request->getAttribute(LoginInput::class);

        // одно исключение на «нет пользователя» и «неверный пароль»:
        // иначе перебором составляется список зарегистрированных адресов
        $user = $this->auth->authenticate($input->email, $input->plainPassword);
        $pair = $this->tokens->issueFor($user, $request->getHeaderLine('User-Agent'));

        return $this->responseFactory
            ->createResponse([
                'accessToken' => $pair->accessToken->value,
                'expiresIn' => $pair->accessToken->expiresIn(),
                'refreshToken' => $pair->refreshToken,
                'tokenType' => 'Bearer',
            ])
            // ответ с токенами не должен осесть в кеше прокси
            ->withHeader('Cache-Control', 'no-store')
            ->withHeader('Pragma', 'no-cache');
    }
}
