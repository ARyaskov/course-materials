<?php

declare(strict_types=1);

namespace App\Infrastructure\Directory;

use App\Domain\Directory\DirectoryClientInterface;
use App\Domain\Directory\Employee;
use App\Domain\Directory\Exception\DirectoryUnavailableException;
use Psr\Http\Client\ClientExceptionInterface;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Psr\Log\LoggerInterface;

final readonly class ResilientDirectoryClient implements DirectoryClientInterface
{
    private const RETRYABLE_STATUSES = [429, 502, 503, 504];
    private const MAX_ATTEMPTS = 3;

    public function __construct(
        private ClientInterface $http,
        private RequestFactoryInterface $requestFactory,
        private CircuitBreaker $breaker,
        private LoggerInterface $logger,
        private string $baseUri,
    ) {
    }

    public function findByEmail(string $email): ?Employee
    {
        // предохранитель разомкнут — не тратим тайм-аут впустую
        if (!$this->breaker->isAvailable()) {
            throw new DirectoryUnavailableException('Справочник недоступен (circuit open)');
        }

        $request = $this->requestFactory
            ->createRequest('GET', $this->baseUri . '/employees?email=' . urlencode($email));

        $lastError = null;

        for ($attempt = 1; $attempt <= self::MAX_ATTEMPTS; $attempt++) {
            try {
                $response = $this->http->sendRequest($request);
                $status = $response->getStatusCode();

                if ($status === 404) {
                    $this->breaker->recordSuccess();

                    return null;                    // отсутствие — валидный ответ
                }

                if ($status >= 200 && $status < 300) {
                    $this->breaker->recordSuccess();

                    return Employee::fromArray(
                        json_decode((string) $response->getBody(), true, 16, JSON_THROW_ON_ERROR),
                    );
                }

                if (!in_array($status, self::RETRYABLE_STATUSES, true)) {
                    $this->breaker->recordSuccess();  // сервис жив, ответ отрицательный

                    throw new DirectoryUnavailableException("Справочник вернул {$status}");
                }

                $lastError = "HTTP {$status}";
                $this->sleepBeforeRetry($attempt, $response->getHeaderLine('Retry-After'));
            } catch (ClientExceptionInterface $e) {
                $lastError = $e->getMessage();
                $this->sleepBeforeRetry($attempt, '');
            }

            $this->logger->warning('Повтор запроса к справочнику', [
                'attempt' => $attempt,
                'error' => $lastError,
            ]);
        }

        $this->breaker->recordFailure();

        throw new DirectoryUnavailableException(
            sprintf('Справочник недоступен после %d попыток: %s', self::MAX_ATTEMPTS, $lastError),
        );
    }

    private function sleepBeforeRetry(int $attempt, string $retryAfter): void
    {
        if (is_numeric($retryAfter)) {
            usleep((int) min((float) $retryAfter, 5.0) * 1_000_000);

            return;
        }

        // экспоненциальная задержка с джиттером: клиенты не бьют залпом
        $baseMs = 100 * (2 ** ($attempt - 1));
        $jitterMs = random_int(0, (int) $baseMs);

        usleep(($baseMs + $jitterMs) * 1000);
    }
}
