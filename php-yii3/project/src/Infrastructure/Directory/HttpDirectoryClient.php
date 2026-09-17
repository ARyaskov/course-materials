<?php

declare(strict_types=1);

namespace App\Infrastructure\Directory;

use App\Domain\Directory\Exception\{DirectoryUnavailableException, InvalidDirectoryResponseException};
use App\Domain\Directory\{DirectoryClientInterface, Employee};
use Psr\Http\Client\{ClientExceptionInterface, ClientInterface};
use Psr\Http\Message\{RequestFactoryInterface, ResponseInterface};

final readonly class HttpDirectoryClient implements DirectoryClientInterface
{
    public function __construct(
        private ClientInterface $http,
        private RequestFactoryInterface $requestFactory,
        private string $baseUri,
        private string $apiKey,
    ) {
    }

    public function findByEmail(string $email): ?Employee
    {
        $payload = $this->send('/employees?email=' . rawurlencode($email));

        return $payload === null ? null : $this->toEmployee($payload);
    }

    // findManyByEmail() разбивает список на порции по 50: длина URI ограничена,
    // и чужой сервис может не принять сотню значений разом.

    /** @return array<string, mixed>|null */
    private function parse(ResponseInterface $response): ?array
    {
        $status = $response->getStatusCode();

        if ($status === 404) {
            return null;                    // сотрудника нет — валидный ответ
        }

        if ($status >= 300) {
            throw new DirectoryUnavailableException("Справочник вернул {$status}");
        }

        // чужой сервис может вернуть что угодно, включая HTML-страницу ошибки
        try {
            $decoded = json_decode(
                (string) $response->getBody(), true, 16, JSON_THROW_ON_ERROR,
            );
        } catch (\JsonException $e) {
            throw new InvalidDirectoryResponseException('Ответ не является JSON', previous: $e);
        }

        return is_array($decoded) ? $decoded : throw new InvalidDirectoryResponseException(
            'Ожидался объект',
        );
    }

    /** @param array<string, mixed> $payload */
    private function toEmployee(array $payload): Employee
    {
        // ответ внешнего сервиса — такие же внешние данные, как тело запроса
        $email = $payload['email'] ?? null;

        if (!is_string($email) || filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            throw new InvalidDirectoryResponseException('Некорректный e-mail в ответе');
        }

        return new Employee(
            email: mb_strtolower($email),
            name: mb_substr(trim((string) ($payload['name'] ?? '')), 0, 120),
            // ограничиваем длину: чужие данные не должны раздувать нашу базу
            department: mb_substr(trim((string) ($payload['department'] ?? '')), 0, 120),
        );
    }

    public function findManyByEmail(array $emails): array
    {
        if ($emails === []) {
            return [];
        }

        $payload = $this->send('/employees?emails=' . urlencode(implode(',', $emails)));
        $result = [];

        foreach ($payload['items'] ?? [] as $row) {
            $employee = Employee::fromArray($row);
            $result[$employee->email] = $employee;
        }

        return $result;
    }

    private function send(string $path): ?array
    {
        $request = $this->requestFactory->createRequest('GET', $this->baseUri . $path);

        try {
            $response = $this->http->sendRequest($request);
        } catch (ClientExceptionInterface $e) {
            // чужое исключение превращается в своё: домен не знает про PSR-18
            throw new DirectoryUnavailableException($e->getMessage(), previous: $e);
        }

        if ($response->getStatusCode() === 404) {
            return null;
        }

        if ($response->getStatusCode() >= 300) {
            throw new DirectoryUnavailableException(
                'Справочник вернул ' . $response->getStatusCode(),
            );
        }

        return json_decode((string) $response->getBody(), true, 16, JSON_THROW_ON_ERROR);
    }
}
