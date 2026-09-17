<?php
// scripts/check-env.php
declare(strict_types=1);

const REQUIRED_PHP = '8.5.0';

const REQUIRED_EXTENSIONS = [
    'pdo_pgsql', 'mbstring', 'openssl', 'tokenizer', 'xml', 'ctype',
    'json', 'curl', 'bcmath', 'intl', 'fileinfo', 'zip', 'redis',
];

const REQUIRED_INI = [
    'memory_limit' => '256M',
    'max_execution_time' => '30',
    'post_max_size' => '32M',
    'upload_max_filesize' => '32M',
];

$problems = [];

if (version_compare(PHP_VERSION, REQUIRED_PHP, '<')) {
    $problems[] = sprintf('PHP %s, требуется %s или новее', PHP_VERSION, REQUIRED_PHP);
}

foreach (REQUIRED_EXTENSIONS as $extension) {
    if (! extension_loaded($extension)) {
        $problems[] = "не установлено расширение {$extension}";
    }
}

foreach (REQUIRED_INI as $directive => $expected) {
    $actual = ini_get($directive);
    if ($actual === false || $actual === '') {
        $problems[] = "директива {$directive} не задана";
    }
}

if (ini_get('display_errors') === '1' && PHP_SAPI !== 'cli') {
    $problems[] = 'display_errors включён вне CLI — на проде так нельзя';
}

echo 'PHP ' . PHP_VERSION . ' (' . PHP_SAPI . ')' . PHP_EOL;
echo 'Файл конфигурации: ' . (php_ini_loaded_file() ?: 'не найден') . PHP_EOL;
echo 'OPcache: ' . (extension_loaded('Zend OPcache') ? 'есть' : 'нет') . PHP_EOL;
echo str_repeat('-', 50) . PHP_EOL;

if ($problems === []) {
    echo 'Окружение готово к Laravel 13.' . PHP_EOL;
    exit(0);
}

foreach ($problems as $problem) {
    echo '  ! ' . $problem . PHP_EOL;
}

exit(1);
