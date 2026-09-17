<?php

declare(strict_types=1);

namespace App\Application\Import\Message;

use App\Application\Import\{ImportRunRepository, TicketRowMapper};
use App\Domain\Ticket\TicketRepositoryInterface;
use Psr\Log\LoggerInterface;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Queue\Message\MessageInterface;

final readonly class ImportBatchHandler
{
    public function __construct(
        private ConnectionInterface $db,
        private TicketRepositoryInterface $tickets,
        private TicketRowMapper $mapper,
        private ImportRunRepository $runs,
        private LoggerInterface $logger,
    ) {
    }

    public function handle(MessageInterface $message): void
    {
        $payload = $message->getPayload();
        $runId = (int) $payload['runId'];
        $batchNumber = (int) $payload['batchNumber'];

        // идемпотентность: повторная доставка не обработает порцию дважды
        if ($this->runs->isBatchCompleted($runId, $batchNumber)) {
            $this->logger->info('Порция уже обработана, повтор пропущен', [
                'runId' => $runId, 'batchNumber' => $batchNumber,
            ]);

            return;
        }

        $imported = 0;
        $failed = 0;

        // короткая транзакция на порцию: блокировки держатся секунды
        $this->db->transaction(function () use ($payload, &$imported, &$failed, $runId): void {
            foreach ($payload['rows'] as $row) {
                try {
                    $ticket = $this->mapper->toTicket($row);
                } catch (\Throwable $e) {
                    // битая строка не должна ронять всю порцию
                    $failed++;

                    $this->logger->warning('Строка импорта отклонена', [
                        'runId' => $runId,
                        'externalId' => $row['id'] ?? null,
                        'reason' => $e->getMessage(),
                    ]);

                    continue;
                }

                $this->tickets->save($ticket);
                $imported++;
            }
        });

        // отметка о завершении — в той же транзакции, что и данные,
        // иначе повтор при падении между ними обработает порцию заново
        $this->runs->completeBatch($runId, $batchNumber, $imported, $failed);
    }
}
