<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use App\Api\Error\ValidationErrorResponder;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\Hydrator\HydratorInterface;
use Yiisoft\Validator\ValidatorInterface;

final readonly class InputMiddleware implements MiddlewareInterface
{
    /** @param class-string $inputClass */
    public function __construct(
        private string $inputClass,
        private HydratorInterface $hydrator,
        private ValidatorInterface $validator,
        private ValidationErrorResponder $responder,
    ) {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $raw = $request->getParsedBody();

        if (!is_array($raw)) {
            return $this->responder->malformedBody();
        }

        // гидратор сам приведёт "42" к int по объявленному типу свойства
        $input = $this->hydrator->create($this->inputClass, $this->normalize($raw));

        $result = $this->validator->validate($input);

        if (!$result->isValid()) {
            return $this->responder->fromResult($result);
        }

        return $handler->handle($request->withAttribute($this->inputClass, $input));
    }

    /**
     * Нормализация ДО валидации: иначе " Тема " не пройдёт Length(min: 5)
     * из-за пробелов, а сообщение об ошибке собьёт клиента с толку.
     */
    private function normalize(array $raw): array
    {
        foreach (['title', 'description'] as $field) {
            if (isset($raw[$field]) && is_string($raw[$field])) {
                $raw[$field] = trim(preg_replace('/\s+/u', ' ', $raw[$field]) ?? '');
            }
        }

        if (isset($raw['priority']) && is_string($raw['priority'])) {
            $raw['priority'] = strtolower(trim($raw['priority']));
        }

        return $raw;
    }
}
