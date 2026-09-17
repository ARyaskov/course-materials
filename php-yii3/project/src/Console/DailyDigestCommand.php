<?php

declare(strict_types=1);

namespace App\Console;

/**
 * Собрано из фрагмента урока 16.6: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class DailyDigestCommand
{
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $lastRun = $this->state->lastSuccessfulRun('daily-digest');
        $today = new \DateTimeImmutable('today');

        // если планировщик не работал два дня — отправим за оба
        $day = $lastRun?->modify('+1 day') ?? $today;

        while ($day <= $today) {
            $this->queue->push(new DailyDigestMessage($day->format('Y-m-d')));
            $day = $day->modify('+1 day');
        }

        $this->state->markSuccessfulRun('daily-digest', $today);

        return Command::SUCCESS;
    }
}
