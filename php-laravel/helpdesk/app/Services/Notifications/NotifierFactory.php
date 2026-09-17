<?php
// app/Services/Notifications/NotifierFactory.php
declare(strict_types=1);

namespace App\Services\Notifications;

use App\Contracts\Notifier;
use App\Models\User;
use Illuminate\Contracts\Container\Container;

final readonly class NotifierFactory
{
    private const array CHANNELS = [
        'mail'    => MailNotifier::class,
        'webhook' => WebhookNotifier::class,
        'push'    => PushNotifier::class,
    ];

    public function __construct(private Container $container)
    {
    }

    public function for(User $user): Notifier
    {
        $preferred = $user->settings['notification_channel'] ?? 'mail';

        $class = self::CHANNELS[$preferred] ?? MailNotifier::class;

        /** @var Notifier $notifier */
        $notifier = $this->container->make($class);

        return $notifier->supports($user) ? $notifier : $this->container->make(MailNotifier::class);
    }

    /** Явный выбор канала — например, когда канал уже записан в задаче очереди. */
    public function byChannel(string $channel): Notifier
    {
        $class = self::CHANNELS[$channel] ?? MailNotifier::class;

        /** @var Notifier $notifier */
        $notifier = $this->container->make($class);

        return $notifier;
    }

    /** @return list<string> */
    public function available(): array
    {
        return array_keys(self::CHANNELS);
    }
}
