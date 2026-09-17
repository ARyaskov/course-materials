<?php
// app/Services/Crm/HttpCrmClient.php
declare(strict_types=1);

namespace App\Services\Crm;

use App\Contracts\CrmClient;
use App\Exceptions\ExternalServiceUnavailableException;
use App\Models\Ticket;
use App\Support\CircuitBreaker;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;

final readonly class HttpCrmClient implements CrmClient
{
    public function __construct(
        private string $baseUrl,
        private string $apiKey,
        private CircuitBreaker $breaker,
        private int $timeout = 30,
    ) {
    }

    public function pushTicket(Ticket $ticket): string
    {
        return $this->breaker->call(function () use ($ticket): string {
            $response = $this->request()
                // ключ идемпотентности: повтор не создаст вторую запись
                ->withHeader('Idempotency-Key', "ticket-{$ticket->uuid}-{$ticket->updated_at->timestamp}")
                ->post('/tickets', [
                    'external_id' => $ticket->uuid,
                    'subject'     => $ticket->subject,
                    'status'      => $ticket->status->value,
                    'updated_at'  => $ticket->updated_at->toIso8601String(),
                ]);

            if ($response->clientError()) {
                // наша ошибка — повторять бессмысленно, но и цепь размыкать незачем
                logger()->channel('integrations')->error('crm.rejected', [
                    'ticket_id' => $ticket->id,
                    'status'    => $response->status(),
                    'body'      => mb_substr($response->body(), 0, 300),
                ]);

                throw new CrmRejectedException($ticket->id, $response->status());
            }

            if ($response->failed()) {
                throw new ExternalServiceUnavailableException('crm');
            }

            return (string) $response->json('id');
        });
    }

    private function request(): PendingRequest
    {
        return Http::baseUrl($this->baseUrl)
            ->withToken($this->apiKey)
            ->acceptJson()
            ->connectTimeout(2)
            ->timeout($this->timeout)
            ->retry(
                times: 3,
                sleepMilliseconds: fn (int $attempt): int => (int) (300 * (2 ** ($attempt - 1)) + random_int(0, 200)),
                when: fn (\Throwable $e): bool => $e instanceof ConnectionException
                    || ($e instanceof RequestException && $e->response->serverError()),
                throw: false,
            )
            ->withHeader('X-Request-Id', \Illuminate\Support\Facades\Context::get('request_id', ''));
    }
}
