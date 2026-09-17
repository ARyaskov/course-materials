<?php

declare(strict_types=1);

namespace App\Console;

use App\Application\Ticket\ChangeTicketStatusService;
use App\Domain\Ticket\{TicketRepositoryInterface, TicketStatus};
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\{InputInterface, InputOption};
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

#[AsCommand(
    name: 'tickets:close-stale',
    description: 'Закрывает решённые заявки, по которым нет активности N дней',
)]
final class CloseStaleTicketsCommand extends Command
{
    private bool $shouldStop = false;

    public function __construct(
        // те же сервисы, что у HTTP-обработчиков
        private readonly TicketRepositoryInterface $tickets,
        private readonly ChangeTicketStatusService $statusService,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption('days', 'd', InputOption::VALUE_REQUIRED,
                'Сколько дней без активности', '14')
            ->addOption('limit', 'l', InputOption::VALUE_REQUIRED,
                'Максимум заявок за прогон', '500')
            // сухой прогон — обязательная опция для всего, что меняет данные
            ->addOption('dry-run', null, InputOption::VALUE_NONE,
                'Показать, что будет сделано, не изменяя данные');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $this->listenForSignals();

        $days = (int) $input->getOption('days');
        $limit = (int) $input->getOption('limit');
        $dryRun = (bool) $input->getOption('dry-run');

        if ($days < 1) {
            $io->error('Параметр --days должен быть положительным.');

            // ненулевой код: cron и CI увидят провал
            return Command::INVALID;
        }

        $stale = $this->tickets->findStaleResolved($days, $limit);

        if ($stale === []) {
            $io->success('Заявок для закрытия нет.');

            return Command::SUCCESS;
        }

        $io->note(sprintf('Найдено заявок: %d%s', count($stale),
            $dryRun ? ' (сухой прогон)' : ''));

        $closed = 0;
        $progress = $io->createProgressBar(count($stale));

        foreach ($stale as $ticket) {
            if ($this->shouldStop) {
                $io->warning('Остановлено по сигналу.');

                break;
            }

            if (!$dryRun) {
                // тот же сценарий, что вызывает HTTP-обработчик:
                // правила перехода и уведомления работают одинаково
                $this->statusService->changeStatus(
                    $ticket->id, TicketStatus::Closed, SystemUser::SYSTEM_USER_ID,
                );
            }

            $closed++;
            $progress->advance();
            pcntl_signal_dispatch();
        }

        $progress->finish();
        $io->newLine(2);

        $this->logger->info('Закрытие залежавшихся заявок', [
            'closed' => $closed, 'dryRun' => $dryRun, 'interrupted' => $this->shouldStop,
        ]);

        $io->success(sprintf('%s заявок: %d', $dryRun ? 'Было бы закрыто' : 'Закрыто', $closed));

        return Command::SUCCESS;
    }

    private function listenForSignals(): void
    {
        if (!function_exists('pcntl_async_signals')) {
            return;
        }

        pcntl_async_signals(true);

        $handler = function (): void {
            $this->shouldStop = true;
        };

        pcntl_signal(SIGTERM, $handler);
        pcntl_signal(SIGINT, $handler);
    }
}
