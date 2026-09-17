<?php

declare(strict_types=1);

namespace App\Api\Middleware;

/**
 * Собрано из фрагмента урока 7.2: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class RouteNameLogMiddleware
{
    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $response = $handler->handle($request);

        $this->logger->info('Запрос обработан', [
            // 'api/v1/tickets/view' — низкая кардинальность, годится для метрик
            'route' => $this->currentRoute->getName(),
            'status' => $response->getStatusCode(),
        ]);

        return $response;
    }
}
