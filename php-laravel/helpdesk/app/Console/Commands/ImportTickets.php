<?php
// app/Console/Commands/ImportTickets.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\Ticket;
use App\Support\CsvReader;
use Illuminate\Console\Command;

final class ImportTickets extends Command
{
    protected $signature = 'tickets:import {path} {--chunk=500}';

    protected $description = 'Импортирует заявки из CSV';

    public function handle(): int
    {
        $reader = new CsvReader($this->argument('path'));
        $chunkSize = (int) $this->option('chunk');

        $buffer = [];
        $imported = 0;

        foreach ($reader->rows() as $line => $row) {
            $buffer[] = [
                'subject'    => $row['subject'],
                'body'       => $row['body'],
                'priority'   => $row['priority'],
                'author_id'  => (int) $row['author_id'],
                'created_at' => now(),
                'updated_at' => now(),
            ];

            if (count($buffer) >= $chunkSize) {
                Ticket::query()->insert($buffer);
                $imported += count($buffer);
                $buffer = [];

                $this->output->write('.');
            }
        }

        if ($buffer !== []) {
            Ticket::query()->insert($buffer);
            $imported += count($buffer);
        }

        $this->newLine();
        $this->info("Импортировано: {$imported}");

        return self::SUCCESS;
    }
}
