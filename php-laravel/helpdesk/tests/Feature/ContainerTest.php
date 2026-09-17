<?php
// tests/Feature/ContainerTest.php
declare(strict_types=1);

use App\Contracts\Notifier;
use App\Services\Notifications\MailNotifier;
use App\Services\Notifications\QueueNotifier;
use App\Services\NotificationDispatcher;

it('в production оборачивает уведомления в очередь', function (): void {
    app()->detectEnvironment(fn (): string => 'production');
    app()->forgetInstance(Notifier::class);

    expect(app(Notifier::class))->toBeInstanceOf(QueueNotifier::class);
});

it('локально отправляет напрямую', function (): void {
    expect(app(Notifier::class))->toBeInstanceOf(MailNotifier::class);
});

it('singleton возвращает один объект', function (): void {
    expect(app(\App\Contracts\AgentDirectory::class))
        ->toBe(app(\App\Contracts\AgentDirectory::class));
});

it('bind возвращает разные объекты', function (): void {
    app()->bind('test.service', fn () => new stdClass());

    expect(app('test.service'))->not->toBe(app('test.service'));
});

it('метки собирают все реализации', function (): void {
    $dispatcher = app(NotificationDispatcher::class);

    $reflection = new ReflectionProperty($dispatcher, 'notifiers');
    $notifiers = iterator_to_array($reflection->getValue($dispatcher));

    expect($notifiers)->toHaveCount(3);
});

it('контекстная привязка даёт разные реализации', function (): void {
    $escalation = app(\App\Services\TicketEscalationService::class);
    $tickets = app(\App\Services\TicketService::class);

    $a = new ReflectionProperty($escalation, 'notifier');
    $b = new ReflectionProperty($tickets, 'notifier');

    expect($a->getValue($escalation))->not->toBeInstanceOf($b->getValue($tickets)::class);
});

it('все интерфейсы проекта имеют привязку', function (): void {
    $interfaces = collect(glob(app_path('Contracts/*.php')))
        ->map(fn (string $file): string => 'App\\Contracts\\' . basename($file, '.php'));

    foreach ($interfaces as $interface) {
        expect(app()->bound($interface))->toBeTrue("Интерфейс {$interface} не привязан");
    }
});
