<?php
// tests/Feature/NotifierTest.php
declare(strict_types=1);

use App\Contracts\Notifier;
use App\Models\Ticket;
use App\Models\User;
use App\Services\Notifications\CircuitBreakerNotifier;
use App\Services\Notifications\LoggingNotifier;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Tests\Doubles\FakeNotifier;

it('подменяет реализацию одной строкой', function (): void {
    $fake = new FakeNotifier();
    $this->app->instance(Notifier::class, $fake);

    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    expect($fake->sentTo($ticket->author))->toHaveCount(1);
});

it('декоратор логирования не меняет поведение', function (): void {
    Log::spy();

    $fake = new FakeNotifier();
    $notifier = new LoggingNotifier($fake, logger());

    $user = User::factory()->create();
    $notifier->send($user, 'Тема', 'Текст');

    expect($fake->sent)->toHaveCount(1);
    Log::shouldHaveReceived('info')->withArgs(fn (string $m): bool => $m === 'notification.sent');
});

it('предохранитель размыкает цепь после серии сбоев', function (): void {
    Cache::flush();

    $failing = new class implements Notifier {
        public function send(User $recipient, string $subject, string $body): void
        {
            throw new \RuntimeException('сервис недоступен');
        }

        public function supports(User $recipient): bool
        {
            return true;
        }

        public function channel(): string
        {
            return 'failing';
        }
    };

    $notifier = new CircuitBreakerNotifier($failing);
    $user = User::factory()->create();

    foreach (range(1, 5) as $i) {
        try {
            $notifier->send($user, 'Тема', 'Текст');
        } catch (\Throwable) {
            //
        }
    }

    expect(fn () => $notifier->send($user, 'Тема', 'Текст'))
        ->toThrow(\App\Exceptions\ExternalServiceUnavailableException::class);
});

it('фабрика выбирает канал по настройкам пользователя', function (): void {
    $user = User::factory()->create([
        'webhook_url' => 'https://example.com/hook',
        'settings'    => ['notification_channel' => 'webhook'],
    ]);

    $notifier = app(\App\Services\Notifications\NotifierFactory::class)->for($user);

    expect($notifier->channel())->toBe('webhook');
});

it('фабрика откатывается на почту при неподдерживаемом канале', function (): void {
    $user = User::factory()->create([
        'webhook_url' => null,
        'settings'    => ['notification_channel' => 'webhook'],
    ]);

    expect(app(\App\Services\Notifications\NotifierFactory::class)->for($user)->channel())->toBe('mail');
});

it('все реализации соблюдают контракт', function (string $class): void {
    $notifier = app($class);

    expect($notifier)->toBeInstanceOf(Notifier::class)
        ->and($notifier->channel())->toBeString()->not->toBeEmpty();
})->with([
    \App\Services\Notifications\MailNotifier::class,
    \App\Services\Notifications\WebhookNotifier::class,
    \App\Services\Notifications\PushNotifier::class,
]);
