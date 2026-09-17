<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Storage\FileStorageInterface;
use App\Domain\Ticket\{AttachmentId, AttachmentRepositoryInterface, TicketRepositoryInterface};

final readonly class DownloadAttachmentService
{
    public function __construct(
        private AttachmentRepositoryInterface $attachments,
        private TicketRepositoryInterface $tickets,
        private FileStorageInterface $storage,
        private TicketPolicy $policy,
        private CurrentUser $currentUser,
    ) {
    }

    public function download(AttachmentId $id): AttachmentDownload
    {
        $attachment = $this->attachments->getById($id);
        $ticket = $this->tickets->getById($attachment->ticketId);

        // права проверяются ВСЕГДА, независимо от способа выдачи
        $this->policy->assertCanView(
            $ticket, $this->currentUser->id(), $this->currentUser->role(),
        );

        // если хранилище умеет подписанные ссылки — отдаём редирект,
        // и трафик файла не проходит через воркеры PHP
        $url = $this->storage->temporaryUrl($attachment->path, new \DateInterval('PT5M'));

        return $url !== null
            ? AttachmentDownload::redirect($url, $attachment)
            : AttachmentDownload::stream($this->storage->get($attachment->path), $attachment);
    }
}
