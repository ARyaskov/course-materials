<?php
// config/helpdesk.php
declare(strict_types=1);

return [
    'limits' => [
        'open_tickets_per_user' => (int) env('HELPDESK_OPEN_LIMIT', 20),
        'tags_per_ticket'       => 5,
        'attachments_per_ticket'=> 10,
    ],

    'sla' => [
        'default_hours'  => (int) env('HELPDESK_SLA_HOURS', 24),
        'escalate_after' => (int) env('HELPDESK_ESCALATE_HOURS', 48),
    ],

    'attachments' => [
        'max_size_mb'   => (int) env('HELPDESK_ATTACHMENT_MB', 16),
        'disk'          => env('HELPDESK_DISK', 'private'),
        'allowed_mimes' => ['image/png', 'image/jpeg', 'application/pdf', 'text/plain'],
    ],

    'notifications' => [
        'default_channel' => env('HELPDESK_CHANNEL', 'mail'),
        'channels'        => ['mail', 'webhook', 'push'],
    ],
];
