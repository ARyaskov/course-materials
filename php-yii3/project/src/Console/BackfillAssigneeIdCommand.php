<?php

declare(strict_types=1);

namespace App\Console;

use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Yiisoft\Db\Connection\ConnectionInterface;

#[AsCommand(
    name: 'tickets:backfill-assignee-id',
    description: 'Заполняет ticket.assignee_id по ticket.assignee батчами',
)]
final class BackfillAssigneeIdCommand extends Command
{
    private bool $shouldStop = false;

    public function __construct(
        private readonly ConnectionInterface $db,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addOption('batch', null, InputOption::VALUE_REQUIRED, 'Размер батча', '1000');
        $this->addOption('pause', null, InputOption::VALUE_REQUIRED, 'Пауза, мс', '100');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        pcntl_async_signals(true);
        pcntl_signal(SIGTERM, fn () => $this->shouldStop = true);
        pcntl_signal(SIGINT, fn () => $this->shouldStop = true);

        $batch = (int) $input->getOption('batch');
        $pauseUs = ((int) $input->getOption('pause')) * 1000;
        $total = 0;

        while (!$this->shouldStop) {
            // каждый батч — своя короткая транзакция
            $affected = $this->db->transaction(
                fn (): int => $this->db->createCommand(
                    'UPDATE ticket t
                     SET assignee_id = u.id
                     FROM "user" u
                     WHERE t.id IN (
                         SELECT id FROM ticket
                         WHERE assignee_id IS NULL AND assignee IS NOT NULL
                         ORDER BY id
                         LIMIT :limit
                         FOR UPDATE SKIP LOCKED
                     )
                     AND u.email = t.assignee',
                    [':limit' => $batch],
                )->execute(),
            );

            if ($affected === 0) {
                break;                       // всё перенесено
            }

            $total += $affected;
            $output->writeln(sprintf('Перенесено: %d', $total));

            // даём базе передышку: автовакуум и обычные запросы
            usleep($pauseUs);
        }

        $this->logger->info('Backfill завершён', [
            'total' => $total,
            'interrupted' => $this->shouldStop,
        ]);

        return Command::SUCCESS;
    }
}
