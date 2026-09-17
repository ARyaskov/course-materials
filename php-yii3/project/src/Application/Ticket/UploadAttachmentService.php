<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Storage\AttachmentStorageInterface;
use App\Domain\Ticket\{Attachment, AttachmentRepositoryInterface, TicketRepositoryInterface};
use App\Domain\Ticket\Exception\{InvalidAttachmentException, StorageException};
use Psr\Http\Message\UploadedFileInterface;
use Psr\Log\LoggerInterface;

final readonly class UploadAttachmentService
{
    private const MAX_BYTES = 10 * 1024 * 1024;

    /** Расширение → допустимые MIME-типы, определённые по содержимому. */
    private const ALLOWED = [
        'pdf' => ['application/pdf'],
        'png' => ['image/png'],
        'jpg' => ['image/jpeg'],
        'jpeg' => ['image/jpeg'],
        'txt' => ['text/plain'],
        'log' => ['text/plain'],
        'csv' => ['text/plain', 'text/csv'],
    ];

    public function __construct(
        private TicketRepositoryInterface $tickets,
        private AttachmentRepositoryInterface $attachments,
        private AttachmentStorageInterface $storage,
        private TicketPolicy $policy,
        private CurrentUser $currentUser,
        private LoggerInterface $logger,
    ) {
    }

    public function upload(UploadAttachmentCommand $command): Attachment
    {
        $ticket = $this->tickets->getById($command->ticketId);

        // права на заявку проверяются до всякой работы с файлом
        $this->policy->assertCanComment(
            $ticket, $this->currentUser->id(), $this->currentUser->role(),
        );

        $file = $command->file;

        $this->assertUploadSucceeded($file);
        $extension = $this->assertAllowedType($file);

        // имя генерируем сами: клиентское не участвует в пути
        $storageName = bin2hex(random_bytes(16)) . '.' . $extension;

        $path = $this->storage->store(
            $command->ticketId,
            $storageName,
            // поток, а не строка: файл на 10 МБ не грузится в память целиком
            $file->getStream(),
        );

        $attachment = Attachment::create(
            ticketId: $command->ticketId,
            path: $path,
            // исходное имя сохраняем отдельным полем — для показа пользователю
            originalName: $this->safeOriginalName($file->getClientFilename()),
            mimeType: $this->detectMime($file),
            sizeBytes: (int) $file->getSize(),
            uploadedBy: $command->uploadedBy,
        );

        try {
            $this->attachments->save($attachment);
        } catch (\Throwable $e) {
            // файл записан, метаданные — нет: убираем осиротевший файл
            $this->storage->delete($path);

            throw $e;
        }

        return $attachment;
    }

    private function assertUploadSucceeded(UploadedFileInterface $file): void
    {
        if ($file->getError() !== UPLOAD_ERR_OK) {
            throw InvalidAttachmentException::uploadFailed($file->getError());
        }

        // размер проверяем до чтения содержимого
        if ($file->getSize() === null || $file->getSize() > self::MAX_BYTES) {
            throw InvalidAttachmentException::tooLarge(self::MAX_BYTES);
        }

        if ($file->getSize() === 0) {
            throw InvalidAttachmentException::empty();
        }
    }

    /** @return string расширение из белого списка */
    private function assertAllowedType(UploadedFileInterface $file): string
    {
        $clientName = (string) $file->getClientFilename();
        $extension = strtolower(pathinfo($clientName, PATHINFO_EXTENSION));

        if (!isset(self::ALLOWED[$extension])) {
            throw InvalidAttachmentException::forbiddenExtension($extension);
        }

        $detected = $this->detectMime($file);

        // тип определён по содержимому и должен соответствовать расширению:
        // «shell.php», переименованный в «report.pdf», не пройдёт
        if (!in_array($detected, self::ALLOWED[$extension], true)) {
            $this->logger->warning('Тип файла не соответствует расширению', [
                'extension' => $extension, 'detected' => $detected,
            ]);

            throw InvalidAttachmentException::typeMismatch($extension, $detected);
        }

        return $extension;
    }

    /** Тип по содержимому, а не по заголовку Content-Type от клиента. */
    private function detectMime(UploadedFileInterface $file): string
    {
        $stream = $file->getStream();
        $stream->rewind();

        // достаточно первых килобайт: сигнатура файла в начале
        $head = $stream->read(4096);
        $stream->rewind();

        return (new \finfo(FILEINFO_MIME_TYPE))->buffer($head) ?: 'application/octet-stream';
    }

    private function safeOriginalName(?string $name): string
    {
        if ($name === null || $name === '') {
            return 'file';
        }

        // только базовое имя, без управляющих символов и нулевого байта
        $name = basename(str_replace(['\\', "\0", "\r", "\n"], '', $name));

        return mb_substr($name, 0, 255);
    }
}
