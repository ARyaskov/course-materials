<?php

declare(strict_types=1);

namespace App\Infrastructure\Webhook;

/**
 * Собрано из фрагмента урока 17.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class HttpWebhookSender
{
    public function send(string $url, WebhookPayload $payload): void
    {
        // адрес задаёт пользователь — проверяем хост по белому списку:
        // иначе получим SSRF к внутренним сервисам и метаданным облака
        $host = parse_url($url, PHP_URL_HOST);

        if (!is_string($host) || !in_array($host, $this->allowedHosts, true)) {
            throw new \InvalidArgumentException("Недопустимый адрес вебхука: {$url}");
        }

        $body = json_encode($payload->toArray(), JSON_THROW_ON_ERROR);
        $timestamp = time();

        $request = $this->requestFactory
            ->createRequest('POST', $url)
            ->withHeader('Content-Type', 'application/json')
            // повтор не создаст у получателя второй записи
            ->withHeader('Idempotency-Key', $payload->eventId)
            // защита от воспроизведения старого запроса
            ->withHeader('X-HelpDesk-Timestamp', (string) $timestamp)
            // подпись: получатель убедится, что запрос от нас
            ->withHeader('X-HelpDesk-Signature', hash_hmac(
                'sha256', $timestamp . '.' . $body, $this->signingSecret,
            ))
            ->withBody($this->streamFactory->createStream($body));

        $response = $this->http->sendRequest($request);

        if ($response->getStatusCode() >= 300) {
            throw new WebhookDeliveryException(
                sprintf('Получатель вернул %d', $response->getStatusCode()),
            );
        }
    }
}
