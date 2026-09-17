<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Application\Ticket\DownloadAttachmentService;
use App\Domain\Ticket\AttachmentId;
use Psr\Http\Message\ResponseFactoryInterface;
use Psr\Http\Message\ResponseInterface;
use Yiisoft\Http\Status;
use Yiisoft\Router\CurrentRoute;

/** Выдача вложения из уроков 17.3 и 17.4: заголовки безопасности и поток вместо строки. */
final readonly class DownloadAttachmentAction
{
    public function __construct(
        private DownloadAttachmentService $service,
        private ResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(CurrentRoute $route): ResponseInterface
    {
        // сервис проверил права на заявку, к которой прикреплён файл
        $download = $this->service->download(AttachmentId::fromInt((int) $route->getArgument('id')));

        return $this->responseFactory
            ->createResponse(Status::OK)
            // тип из нашей базы, а не из того, что прислал клиент при загрузке
            ->withHeader('Content-Type', $download->mimeType)
            ->withHeader('Content-Length', (string) $download->sizeBytes)
            ->withHeader('Content-Disposition', sprintf(
                'attachment; filename="%s"; filename*=UTF-8\'\'%s',
                preg_replace('/[^\x20-\x7E]/', '_', $download->originalName) ?? 'file',
                rawurlencode($download->originalName),
            ))
            ->withHeader('X-Content-Type-Options', 'nosniff')
            ->withHeader('Cache-Control', 'private, max-age=300')
            // тело — поток: файл не читается в память
            ->withBody($download->stream);
    }
}
