<?php

declare(strict_types=1);

namespace App\Console;

use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\{InputInterface, InputOption};
use Symfony\Component\Console\Output\OutputInterface;
use Yiisoft\Db\Connection\ConnectionInterface;

#[AsCommand(
    name: 'queue:release-stuck',
    description: 'Возвращает в очередь сообщения, зависшие в резервации',
)]
final class QueueReleaseStuckCommand extends Command
{
    public function __construct(
        private readonly ConnectionInterface $db,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addOption('timeout', null, InputOption::VALUE_REQUIRED,
            'Сколько секунд считать резервацию зависшей', '900');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $timeout = (int) $input->getOption('timeout');

        $released = $this->db->createCommand(
            'UPDATE {{%queue_message}}
             SET reserved_at = NULL, attempt = attempt + 1
             WHERE reserved_at IS NOT NULL
               AND done_at IS NULL
               AND reserved_at < :threshold',
            [':threshold' => time() - $timeout],
        )->execute();

        if ($released > 0) {
            // ненулевое значение означает, что воркеры падают — это стоит заметить
            $this->logger->warning('Возвращены зависшие сообщения', [
                'count' => $released, 'timeoutSeconds' => $timeout,
            ]);
        }

        $output->writeln(sprintf('Возвращено в очередь: %d', $released));

        return Command::SUCCESS;
    }
}
