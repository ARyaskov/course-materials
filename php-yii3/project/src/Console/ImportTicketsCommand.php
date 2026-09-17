<?php

declare(strict_types=1);

namespace App\Console;

use App\Application\Import\ImportRunRepository;
use App\Application\Import\Message\ImportBatchMessage;
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\{InputArgument, InputInterface, InputOption};
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;
use Yiisoft\Queue\QueueInterface;

#[AsCommand(
    name: 'tickets:import',
    description: 'Импортирует заявки из CSV порциями через очередь',
)]
final class ImportTicketsCommand extends Command
{
    private bool $shouldStop = false;

    public function __construct(
        private readonly QueueInterface $queue,
        private readonly ImportRunRepository $runs,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addArgument('source', InputArgument::REQUIRED, 'Путь к CSV-файлу')
            ->addOption('batch', 'b', InputOption::VALUE_REQUIRED, 'Строк в порции', '500')
            ->addOption('resume', null, InputOption::VALUE_REQUIRED,
                'Продолжить прогон с указанным id')
            ->addOption('dry-run', null, InputOption::VALUE_NONE,
                'Проверить файл, не ставя задач');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $this->listenForSignals();

        $source = (string) $input->getArgument('source');
        $batchSize = (int) $input->getOption('batch');
        $dryRun = (bool) $input->getOption('dry-run');

        if (!is_readable($source)) {
            $io->error("Файл недоступен: {$source}");

            return Command::INVALID;
        }

        $run = $input->getOption('resume') !== null
            ? $this->runs->getById((int) $input->getOption('resume'))
            : $this->runs->start($source, hash_file('xxh128', $source));

        $io->title(sprintf('Импорт заявок (прогон %d)', $run->id));

        if ($run->lastDispatchedOffset > 0) {
            $io->note(sprintf('Продолжаем со строки %d', $run->lastDispatchedOffset));
        }

        $batch = [];
        $offset = 0;
        $dispatched = 0;

        // генератор: файл читается потоком, в памяти только текущая порция
        foreach ($this->readRows($source) as $row) {
            $offset++;

            // пропускаем то, что уже отправлено в предыдущем прогоне
            if ($offset <= $run->lastDispatchedOffset) {
                continue;
            }

            $batch[] = $row;

            if (count($batch) < $batchSize) {
                continue;
            }

            if (!$dryRun) {
                $this->dispatchBatch($run->id, $batch, $offset);
            }

            $dispatched++;
            $batch = [];

            if ($dispatched % 20 === 0) {
                $io->writeln(sprintf('Отправлено порций: %d (строк: %d)', $dispatched, $offset));
            }

            // выход на границе порции: состояние согласовано
            pcntl_signal_dispatch();

            if ($this->shouldStop) {
                $io->warning(sprintf(
                    'Остановлено. Продолжить: --resume=%d', $run->id,
                ));

                return Command::SUCCESS;
            }
        }

        // хвост, не набравший полной порции
        if ($batch !== [] && !$dryRun) {
            $this->dispatchBatch($run->id, $batch, $offset);
            $dispatched++;
        }

        $this->runs->markDispatched($run->id, $dispatched, $offset);

        $io->success(sprintf(
            '%s порций: %d, строк: %d',
            $dryRun ? 'Было бы отправлено' : 'Отправлено', $dispatched, $offset,
        ));

        return Command::SUCCESS;
    }

    /**
     * Генератор вместо file(): 2 ГБ файла читаются построчно.
     * @return \Generator<int, array<string, string>>
     */
    private function readRows(string $source): \Generator
    {
        $handle = fopen($source, 'rb') ?: throw new \RuntimeException('Не открыть файл.');

        try {
            $header = fgetcsv($handle);

            while (($row = fgetcsv($handle)) !== false) {
                if (count($row) === count($header)) {
                    yield array_combine($header, $row);
                }
            }
        } finally {
            fclose($handle);
        }
    }

    /** @param list<array<string, string>> $batch */
    private function dispatchBatch(int $runId, array $batch, int $offset): void
    {
        $this->queue->push(new ImportBatchMessage(
            runId: $runId,
            rows: $batch,
            // номер порции нужен для идемпотентности обработчика
            batchNumber: (int) ceil($offset / count($batch)),
        ));

        $this->runs->incrementDispatched($runId, $offset);
    }

    private function listenForSignals(): void
    {
        if (!function_exists('pcntl_async_signals')) {
            return;
        }

        pcntl_async_signals(true);

        $handler = function (int $signal): void {
            $this->shouldStop = true;
            $this->logger->info('Получен сигнал завершения', ['signal' => $signal]);
        };

        pcntl_signal(SIGTERM, $handler);
        pcntl_signal(SIGINT, $handler);
    }
}
