<?php

declare(strict_types=1);

namespace App\Console;

use App\Domain\Storage\FileStorageInterface;
use App\Domain\Ticket\AttachmentRepositoryInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

/** Поиск осиротевших файлов из урока 17.4. */
#[AsCommand(name: 'storage/cleanup', description: 'Удаляет файлы без записи в базе')]
final class StorageCleanupCommand extends Command
{
    public function __construct(
        private readonly FileStorageInterface $storage,
        private readonly AttachmentRepositoryInterface $attachments,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addOption('dry-run', mode: InputOption::VALUE_NONE, description: 'Только показать');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $dryRun = (bool) $input->getOption('dry-run');
        $removed = 0;

        // возраст обязателен: только что загруженный файл может ещё не иметь
        // записи — она создаётся следующей строкой кода в сервисе
        $olderThan = new \DateTimeImmutable('-1 day');

        foreach ($this->storage->listOlderThan($olderThan) as $path) {
            if ($this->attachments->existsByPath($path)) {
                continue;
            }

            $io->writeln("Осиротевший файл: {$path}");

            if (!$dryRun) {
                $this->storage->delete($path);
                $removed++;
            }
        }

        $io->success("Удалено файлов: {$removed}");

        return Command::SUCCESS;
    }
}
