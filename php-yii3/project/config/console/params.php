<?php

declare(strict_types=1);

use App\Console\{CloseStaleTicketsCommand, HealthCommand, ImportStatusCommand,
                 ImportTicketsCommand, QueueReleaseStuckCommand, QueueRetryFailedCommand,
                 RbacInitCommand, ScheduleRunCommand, SendSlaRemindersCommand,
                 StorageCleanupCommand};
use Yiisoft\Db\Migration\Command\{CreateCommand, DownCommand, HistoryCommand,
                                  NewCommand, UpCommand};
use Yiisoft\Queue\Command\{ListenCommand, RunCommand};

return [
    'yiisoft/yii-console' => [
        'commands' => [
            // обслуживание
            'app:health' => HealthCommand::class,
            'rbac:init' => RbacInitCommand::class,

            // заявки
            'tickets:import' => ImportTicketsCommand::class,
            'tickets:close-stale' => CloseStaleTicketsCommand::class,
            'tickets:sla-reminders' => SendSlaRemindersCommand::class,

            // очередь
            'queue:run' => RunCommand::class,
            'queue:listen' => ListenCommand::class,
            'queue:release-stuck' => QueueReleaseStuckCommand::class,
            'queue:retry-failed' => QueueRetryFailedCommand::class,

            // расписание и хранилище
            'schedule:run' => ScheduleRunCommand::class,
            'storage:cleanup' => StorageCleanupCommand::class,
            'import:status' => ImportStatusCommand::class,

            // миграции
            'migrate:create' => CreateCommand::class,
            'migrate:up' => UpCommand::class,
            'migrate:down' => DownCommand::class,
            'migrate:history' => HistoryCommand::class,
            'migrate:new' => NewCommand::class,
        ],
    ],

    'app' => [
        'schedule' => [
            ['name' => 'sla-reminders', 'command' => 'tickets:sla-reminders',
             'cron' => '*/5 * * * *', 'maxRuntimeSeconds' => 120],

            ['name' => 'release-stuck', 'command' => 'queue:release-stuck',
             'cron' => '*/15 * * * *', 'maxRuntimeSeconds' => 60],

            ['name' => 'close-stale', 'command' => 'tickets:close-stale',
             'cron' => '0 3 * * *', 'maxRuntimeSeconds' => 1800],

            ['name' => 'storage-cleanup', 'command' => 'storage:cleanup',
             'cron' => '0 4 * * 0', 'maxRuntimeSeconds' => 3600],
        ],
    ],
];
