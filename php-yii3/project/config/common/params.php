<?php

declare(strict_types=1);

use App\Application\Import\Message\{ImportBatchHandler, ImportBatchMessage};
use App\Application\Report\Message\{ExportReportHandler, ExportReportMessage};
use App\Application\Ticket\Message\{EscalateTicketHandler, EscalateTicketMessage,
                                     NotifyAssigneeHandler, NotifyAssigneeMessage,
                                     SendSurveyHandler, SendSurveyMessage,
                                     SlaReminderHandler, SlaReminderMessage};

return [
    'yiisoft/queue' => [
        'handlers' => [
            NotifyAssigneeMessage::TYPE => [NotifyAssigneeHandler::class, 'handle'],
            SlaReminderMessage::TYPE => [SlaReminderHandler::class, 'handle'],
            EscalateTicketMessage::TYPE => [EscalateTicketHandler::class, 'handle'],
            SendSurveyMessage::TYPE => [SendSurveyHandler::class, 'handle'],
            ExportReportMessage::TYPE => [ExportReportHandler::class, 'handle'],
            ImportBatchMessage::TYPE => [ImportBatchHandler::class, 'handle'],
        ],

        // каналы разделены по требованиям ко времени обработки
        'channels' => ['default', 'reports', 'import'],
    ],
];
