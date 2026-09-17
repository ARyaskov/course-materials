<?php
declare(strict_types=1);

use App\Domain\Storage\AttachmentStorageInterface;
use App\Infrastructure\Storage\{LocalAttachmentStorage, S3AttachmentStorage};
use Psr\Container\ContainerInterface;

/** @var array $params */

return [
    AttachmentStorageInterface::class => static function (ContainerInterface $c) use ($params): AttachmentStorageInterface {
        $config = $params['app']['storage'];

        return $config['driver'] === 's3'
            ? new S3AttachmentStorage($c->get(S3ClientInterface::class), $config['bucket'])
            : new LocalAttachmentStorage($config['path'], $config['url']);
    },
];
