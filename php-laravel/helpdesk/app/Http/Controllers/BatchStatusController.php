<?php
// app/Http/Controllers/BatchStatusController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Bus;

final class BatchStatusController extends Controller
{
    public function show(string $batchId): JsonResponse
    {
        $batch = Bus::findBatch($batchId);

        abort_if($batch === null, 404, 'Пачка не найдена.');

        return $this->ok([
            'id'        => $batch->id,
            'name'      => $batch->name,
            'total'     => $batch->totalJobs,
            'pending'   => $batch->pendingJobs,
            'failed'    => $batch->failedJobs,
            'progress'  => $batch->progress(),
            'finished'  => $batch->finished(),
            'cancelled' => $batch->cancelled(),
        ]);
    }

    public function destroy(string $batchId): JsonResponse
    {
        $batch = Bus::findBatch($batchId);

        abort_if($batch === null, 404);

        $batch->cancel();

        return $this->ok(['id' => $batch->id, 'cancelled' => true]);
    }
}
