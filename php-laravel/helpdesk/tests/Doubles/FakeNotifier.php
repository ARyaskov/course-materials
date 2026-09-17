<?php
// tests/Doubles/FakeNotifier.php
declare(strict_types=1);

namespace Tests\Doubles;

use App\Contracts\Notifier;
use App\Models\User;

final class FakeNotifier implements Notifier
{
    /** @var list<array{user: int, subject: string, body: string}> */
    public array $sent = [];

    public bool $shouldFail = false;

    public function send(User $recipient, string $subject, string $body): void
    {
        if ($this->shouldFail) {
            throw new \App\Exceptions\ExternalServiceUnavailableException('notifier');
        }

        $this->sent[] = ['user' => $recipient->id, 'subject' => $subject, 'body' => $body];
    }

    public function supports(User $recipient): bool
    {
        return true;
    }

    public function channel(): string
    {
        return 'fake';
    }

    /** @return list<array{user: int, subject: string, body: string}> */
    public function sentTo(User $user): array
    {
        return array_values(array_filter($this->sent, fn (array $r): bool => $r['user'] === $user->id));
    }

    public function assertSentTo(User $user, ?string $contains = null): void
    {
        $messages = $this->sentTo($user);

        expect($messages)->not->toBeEmpty("Уведомление для {$user->id} не отправлено");

        if ($contains !== null) {
            expect(collect($messages)->pluck('body')->implode(' '))->toContain($contains);
        }
    }
}
