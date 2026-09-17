<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

/**
 * Собрано из фрагмента урока 17.3: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class UploadAttachmentAction
{
    public function __invoke(ServerRequestInterface $request, CurrentRoute $route): ResponseInterface
    {
        // PSR-7 разбирает multipart сам: файлы приходят объектами UploadedFileInterface
        $files = $request->getUploadedFiles()['files'] ?? [];
        $files = is_array($files) ? $files : [$files];

        if (count($files) > self::MAX_FILES) {
            return $this->error('too_many_files',
                sprintf('Не больше %d файлов за раз.', self::MAX_FILES),
                Status::UNPROCESSABLE_ENTITY);
        }

        $attachments = array_map(
            fn (UploadedFileInterface $file): Attachment => $this->service->upload(
                new UploadAttachmentCommand(
                    ticketId: TicketId::fromInt((int) $route->getArgument('id')),
                    file: $file,
                    uploadedBy: UserId::fromInt(
                        (int) $request->getAttribute(AuthMiddleware::USER_ID),
                    ),
                ),
            ),
            $files,
        );

        return $this->responseFactory->createResponse(
            ['items' => array_map(AttachmentView::fromEntity(...), $attachments)],
            Status::CREATED,
        );
    }
}
