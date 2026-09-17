<?php

declare(strict_types=1);

namespace App\Api\Action\Report;

/**
 * Собрано из фрагмента урока 16.3: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class RequestExportAction
{
    public function __invoke(ServerRequestInterface $request): ResponseInterface
    {
        $exportId = $this->service->requestExport(/* ... */);

        return $this->responseFactory
            ->createResponse(
                ['exportId' => $exportId, 'status' => 'queued'],
                // 202: принято к исполнению, результата ещё нет
                Status::ACCEPTED,
            )
            ->withHeader('Location', $this->urlGenerator->generate(
                'api/v1/reports/status', ['id' => $exportId],
            ));
    }
}
