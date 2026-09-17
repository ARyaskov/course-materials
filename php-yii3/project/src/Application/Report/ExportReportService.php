<?php

declare(strict_types=1);

namespace App\Application\Report;

use App\Application\Report\Message\ExportReportMessage;
use App\Domain\User\UserId;
use Yiisoft\Queue\QueueInterface;

final readonly class ExportReportService
{
    public function __construct(
        // явно указываем нужный канал в определении контейнера
        private QueueInterface $reportsQueue,
    ) {
    }

    public function requestExport(ReportFilter $filter, UserId $requestedBy): string
    {
        $exportId = bin2hex(random_bytes(8));

        // долгая работа не мешает уведомлениям в default
        $this->reportsQueue->push(new ExportReportMessage(
            exportId: $exportId,
            filter: $filter->toArray(),
            requestedBy: $requestedBy->value,
        ));

        return $exportId;
    }
}
