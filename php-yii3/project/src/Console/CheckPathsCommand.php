<?php

declare(strict_types=1);

namespace App\Console;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Yiisoft\Aliases\Aliases;

#[AsCommand(name: 'app:check-paths', description: 'Проверяет пути и права на запись')]
final class CheckPathsCommand extends Command
{
    private const WRITABLE = ['@logs', '@runtime/cache', '@attachments', '@mail'];

    public function __construct(private readonly Aliases $aliases)
    {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $failed = false;

        foreach (self::WRITABLE as $alias) {
            $path = $this->aliases->get($alias);
            $exists = is_dir($path);
            $writable = $exists && is_writable($path);

            $output->writeln(sprintf(
                '%-22s %-46s %s',
                $alias,
                $path,
                $writable ? '<info>OK</info>' : '<error>НЕТ ДОСТУПА</error>',
            ));

            $failed = $failed || !$writable;
        }

        return $failed ? Command::FAILURE : Command::SUCCESS;
    }
}
