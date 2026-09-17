<?php

declare(strict_types=1);

namespace App\Console;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Yiisoft\Db\Connection\ConnectionInterface;
use Psr\SimpleCache\CacheInterface;

#[AsCommand(name: 'app:health', description: 'Проверяет доступность зависимостей')]
final class HealthCommand extends Command
{
    public function __construct(
        private readonly ConnectionInterface $db,
        private readonly CacheInterface $cache,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $checks = [
            'db' => fn (): bool => $this->db->createCommand('SELECT 1')->queryScalar() === 1,
            'cache' => function (): bool {
                $key = 'health:' . bin2hex(random_bytes(4));
                $this->cache->set($key, 'ok', 10);

                return $this->cache->get($key) === 'ok';
            },
        ];

        $failed = [];

        foreach ($checks as $name => $check) {
            try {
                if (!$check()) {
                    $failed[] = $name;
                }
            } catch (\Throwable $e) {
                $failed[] = $name . ': ' . $e->getMessage();
            }
        }

        if ($failed !== []) {
            $output->writeln('<error>UNHEALTHY: ' . implode(', ', $failed) . '</error>');

            return Command::FAILURE;
        }

        $output->writeln('<info>OK</info>');

        return Command::SUCCESS;
    }
}
