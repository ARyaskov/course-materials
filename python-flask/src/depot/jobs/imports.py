"""Импорт каталога в фоне."""

import logging
from uuid import UUID

from depot.domain.ids import ImportJobId
from depot.jobs.context import component, job
from depot.services.import_catalog import ImportService
from depot.services.uow import make_uow

log = logging.getLogger(__name__)


@job
def run_import(job_id: str) -> str:
    """Выполнение задания импорта.

    Функция тонкая: собирает сервис и передаёт управление. Логика разбора
    файла живёт в сервисе и покрыта его тестами — без очереди и без воркера.
    """
    service = ImportService(
        uow_factory=make_uow,
        clock=component("clock"),
        queue=component("queue"),
        storage=component("storage"),
    )
    result = service.run(ImportJobId(UUID(job_id)))
    log.info(
        "import finished",
        extra={
            "job_id": job_id,
            "status": str(result.status),
            "succeeded": result.succeeded,
            "failed": result.failed,
        },
    )
    return str(result.status)
