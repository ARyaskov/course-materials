<?php
// config/tickets.php
declare(strict_types=1);

return [
    'max_attachment_mb' => (int) env('TICKET_MAX_ATTACHMENT_MB', 16),
    'default_priority'  => env('TICKET_DEFAULT_PRIORITY', 'normal'),
    'auto_close_days'   => (int) env('TICKET_AUTO_CLOSE_DAYS', 30),
];
