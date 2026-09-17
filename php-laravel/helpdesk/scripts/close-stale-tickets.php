<?php
// scripts/close-stale-tickets.php
declare(strict_types=1);

require __DIR__ . '/../vendor/autoload.php';

const EXIT_OK = 0;
const EXIT_USAGE = 2;
const EXIT_FAILURE = 1;

$options = getopt('', ['days:', 'dry-run', 'help']);

if (isset($options['help']) || ! isset($options['days'])) {
    fwrite(STDOUT, <<<TEXT
        Закрывает заявки, по которым нет активности N дней.

        Использование:
          php scripts/close-stale-tickets.php --days=30 [--dry-run]

        TEXT);

    exit(isset($options['help']) ? EXIT_OK : EXIT_USAGE);
}

$days = filter_var($options['days'], FILTER_VALIDATE_INT);

if ($days === false || $days < 1) {
    fwrite(STDERR, "Ошибка: --days должен быть положительным целым числом\n");
    exit(EXIT_USAGE);
}

$isDryRun = array_key_exists('dry-run', $options);

try {
    $closed = closeStale($days, $isDryRun);

    fwrite(STDOUT, sprintf(
        "%s заявок: %d\n",
        $isDryRun ? 'Будет закрыто' : 'Закрыто',
        $closed,
    ));

    exit(EXIT_OK);
} catch (Throwable $e) {
    fwrite(STDERR, 'Сбой: ' . $e->getMessage() . "\n");
    exit(EXIT_FAILURE);
}
