<?php

declare(strict_types=1);

namespace App\Console;

use App\Domain\User\Permission;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Yiisoft\Rbac\{ManagerInterface, Permission as RbacPermission, Role};

#[AsCommand(name: 'rbac:init', description: 'Создаёт иерархию ролей и разрешений')]
final class RbacInitCommand extends Command
{
    public function __construct(private readonly ManagerInterface $manager)
    {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        // разрешения — атомарные действия
        foreach ([
            Permission::TICKET_VIEW_OWN => 'Просмотр своих заявок',
            Permission::TICKET_VIEW_ANY => 'Просмотр любых заявок',
            Permission::TICKET_CREATE => 'Создание заявки',
            Permission::TICKET_UPDATE_OWN => 'Изменение своих заявок',
            Permission::TICKET_UPDATE_ANY => 'Изменение любых заявок',
            Permission::TICKET_ASSIGN => 'Назначение исполнителя',
            Permission::TICKET_DELETE => 'Удаление заявки',
            Permission::REPORT_VIEW => 'Просмотр отчётов',
            Permission::USER_MANAGE => 'Управление пользователями',
        ] as $name => $description) {
            $this->manager->addPermission(
                (new RbacPermission($name))->withDescription($description),
            );
        }

        // роли
        $this->manager->addRole((new Role('reporter'))->withDescription('Заявитель'));
        $this->manager->addRole((new Role('agent'))->withDescription('Сотрудник поддержки'));
        $this->manager->addRole((new Role('supervisor'))->withDescription('Супервизор'));
        $this->manager->addRole((new Role('admin'))->withDescription('Администратор'));

        // разрешения заявителя
        $this->manager->addChild('reporter', Permission::TICKET_VIEW_OWN);
        $this->manager->addChild('reporter', Permission::TICKET_CREATE);
        $this->manager->addChild('reporter', Permission::TICKET_UPDATE_OWN);

        // агент = заявитель + работа с чужими заявками
        $this->manager->addChild('agent', 'reporter');
        $this->manager->addChild('agent', Permission::TICKET_VIEW_ANY);
        $this->manager->addChild('agent', Permission::TICKET_UPDATE_ANY);
        $this->manager->addChild('agent', Permission::TICKET_ASSIGN);

        // супервизор = агент + отчёты
        $this->manager->addChild('supervisor', 'agent');
        $this->manager->addChild('supervisor', Permission::REPORT_VIEW);

        // администратор = супервизор + управление пользователями и удаление
        $this->manager->addChild('admin', 'supervisor');
        $this->manager->addChild('admin', Permission::USER_MANAGE);
        $this->manager->addChild('admin', Permission::TICKET_DELETE);

        $output->writeln('<info>Иерархия RBAC создана</info>');

        return Command::SUCCESS;
    }
}
