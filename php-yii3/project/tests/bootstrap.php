<?php

declare(strict_types=1);

require_once dirname(__DIR__) . '/vendor/autoload.php';

// TEST_TOKEN задаёт paratest; при обычном прогоне его нет
$token = getenv('TEST_TOKEN') ?: '0';

putenv(sprintf(
    'TEST_DB_DSN=pgsql:host=db;port=5432;dbname=helpdesk_test_%s',
    $token,
));
