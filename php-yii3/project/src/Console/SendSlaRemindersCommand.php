<?php

declare(strict_types=1);

namespace App\Console;

use App\Application\Ticket\Message\SlaReminderMessage;
use App\Domain\Ticket\TicketRepositoryInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\{InputInterface, InputOption};
use Symfony\Component\Console\Output\OutputInterface;
use Yiisoft\Queue\QueueInterface;

#[AsCommand(
    name: 'tickets:sla-reminders',
    description: 'Ставит в очередь напоминания по заявкам с истекающим сроком реакции',
)]
final class SendSlaRemindersCommand extends Command
{
    public function __construct(
        private readonly TicketRepositoryInterface $tickets,
        private readonly QueueInterface $queue,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->addOption('within', null, InputOption::VALUE_REQUIRED,
                'За сколько минут до срока напоминать', '60')
            ->addOption('limit', 'l', InputOption::VALUE_REQUIRED,
                'Максимум за прогон', '500')
            ->addOption('dry-run', null, InputOption::VALUE_NONE, 'Только показать');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $within = (int) $input->getOption('within');
        $limit = (int) $input->getOption('limit');
        $dryRun = (bool) $input->getOption('dry-run');

        $deadline = (new \DateTimeImmutable())->modify("+{$within} minutes");

        // выборка ограничена: прогон не может затронуть всю таблицу
        $tickets = $this->tickets->findApproachingSlaDeadline($deadline, $limit);

        foreach ($tickets as $ticket) {
            if (!$dryRun) {
                // команда только ставит задачу — отправкой займётся воркер
                $this->queue->push(new SlaReminderMessage($ticket->id->value));
            }

            $output->writeln(sprintf('Заявка %d — срок %s',
                $ticket->id->value,
                $ticket->slaDeadline?->format('H:i') ?? '—',
            ));
        }

        $this->logger->info('Напоминания об SLA поставлены в очередь', [
            'count' => count($tickets), 'withinMinutes' => $within, 'dryRun' => $dryRun,
        ]);

        // если упёрлись в лимит, работы больше, чем помещается в один прогон
        if (count($tickets) === $limit) {
            $this->logger->warning('Достигнут лимит прогона напоминаний', ['limit' => $limit]);
        }

        return Command::SUCCESS;
    }
}
