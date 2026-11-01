"""Импорт каталога из файла.

Долгая работа за коротким запросом: обработчик создаёт запись о задании
и ставит задачу, воркер выполняет её порциями. Синхронный импорт на
десятки тысяч строк упирается в таймаут прокси, и клиент повторяет его
целиком — вместе со всеми уже применёнными строками.
"""

import csv
import io
import logging
from collections.abc import Callable, Iterator
from decimal import Decimal, InvalidOperation

from depot.domain.enums import EquipmentCategory, ImportStatus, Permission
from depot.domain.errors import NotFound
from depot.domain.ids import ImportJobId
from depot.domain.models import EquipmentModel, ImportJob
from depot.domain.permissions import require_permission
from depot.services.commands import CallContext, ImportCatalogCommand
from depot.services.protocols import Clock, FileStorage, TaskQueue
from depot.services.uow import UnitOfWork

log = logging.getLogger(__name__)

IMPORT_TASK = "depot.jobs.imports.run_import"

#: размер порции: коммит на каждой строке даёт тысячи транзакций,
#: один коммит в конце — долгую блокировку и потерю всей работы при сбое
BATCH_SIZE = 500

#: сколько ошибок сохранять в отчёте; остальные считаются, но не хранятся —
#: испорченный файл иначе разрастит поле JSON до мегабайтов
MAX_STORED_ERRORS = 50

REQUIRED_COLUMNS = ("title", "category", "daily_rate", "deposit")


class ImportService:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        clock: Clock,
        queue: TaskQueue,
        storage: FileStorage,
    ) -> None:
        self._uow_factory = uow_factory
        self._clock = clock
        self._queue = queue
        self._storage = storage

    def start(self, command: ImportCatalogCommand, ctx: CallContext) -> ImportJob:
        require_permission(ctx.actor, Permission.CATALOG_IMPORT)

        if not self._storage.exists(command.file_key):
            raise NotFound("файл не найден; сначала загрузите его")

        with self._uow_factory() as uow:
            job = ImportJob(
                user_id=ctx.actor.id,
                status=ImportStatus.QUEUED,
                file_key=command.file_key,
            )
            uow.session.add(job)
            uow.flush()
            job_id = job.id

        # постановка после фиксации: задача не должна стартовать раньше,
        # чем воркер сможет увидеть запись о ней
        self._queue.enqueue(IMPORT_TASK, {"job_id": str(job_id)})
        return job

    def get(self, job_id: ImportJobId, ctx: CallContext) -> ImportJob:
        require_permission(ctx.actor, Permission.CATALOG_IMPORT)
        with self._uow_factory() as uow:
            job = uow.session.get(ImportJob, job_id)
            if job is None:
                raise NotFound(f"задание {job_id} не найдено")
            return job

    def run(self, job_id: ImportJobId) -> ImportJob:
        """Выполнение задания воркером.

        Каждая порция фиксируется отдельно, и прогресс виден клиенту
        по ходу работы. Задача идемпотентна на уровне порции: перезапуск
        после сбоя продолжает с сохранённого счётчика, а не с начала.
        """
        with self._uow_factory() as uow:
            job = uow.session.get(ImportJob, job_id)
            if job is None:
                raise NotFound(f"задание {job_id} не найдено")
            if job.status is not ImportStatus.QUEUED:
                # повторный запуск той же задачи — обычное дело для очереди
                # с гарантией «хотя бы один раз»
                return job
            job.status = ImportStatus.RUNNING
            job.started_at = self._clock.now()
            file_key = job.file_key
            start_from = job.processed_rows

        errors: list[str] = []
        succeeded = failed = processed = 0

        try:
            rows = self._read_rows(file_key)
            batch: list[EquipmentModel] = []

            for index, row in enumerate(rows, start=1):
                if index <= start_from:
                    continue
                processed += 1
                try:
                    batch.append(self._to_model(row))
                    succeeded += 1
                except ValueError as exc:
                    failed += 1
                    if len(errors) < MAX_STORED_ERRORS:
                        errors.append(f"строка {index}: {exc}")

                if len(batch) >= BATCH_SIZE:
                    self._flush_batch(job_id, batch, processed, succeeded, failed, errors)
                    batch = []

            self._flush_batch(job_id, batch, processed, succeeded, failed, errors)
            return self._finish(job_id, ImportStatus.DONE, errors)
        except Exception:
            log.exception("import failed", extra={"job_id": str(job_id)})
            # состояние сохраняется даже при падении: иначе задание навсегда
            # застревает в «выполняется»
            return self._finish(job_id, ImportStatus.FAILED, errors)

    def _read_rows(self, file_key: str) -> Iterator[dict[str, str]]:
        """Чтение файла построчно.

        Файл не загружается в память целиком: выгрузка на сто тысяч позиций
        весит десятки мегабайт, и воркеру этого хватит, чтобы упереться
        в предел памяти контейнера.
        """
        raw = self._storage.open(file_key)
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
        reader = csv.DictReader(text)

        missing = set(REQUIRED_COLUMNS) - set(reader.fieldnames or ())
        if missing:
            raise ValueError(f"в файле нет колонок: {', '.join(sorted(missing))}")

        yield from reader

    @staticmethod
    def _to_model(row: dict[str, str]) -> EquipmentModel:
        try:
            category = EquipmentCategory(row["category"].strip())
        except ValueError:
            raise ValueError(f"неизвестная категория {row['category']!r}") from None

        try:
            daily_rate = Decimal(row["daily_rate"].replace(",", ".").strip())
            deposit = Decimal(row["deposit"].replace(",", ".").strip())
        except (InvalidOperation, KeyError):
            raise ValueError("некорректная сумма") from None

        if daily_rate <= 0:
            raise ValueError("ставка должна быть положительной")

        return EquipmentModel(
            title=row["title"].strip(),
            category=category,
            daily_rate=daily_rate,
            deposit=deposit,
            description=(row.get("description") or "").strip() or None,
        )

    def _flush_batch(
        self,
        job_id: ImportJobId,
        batch: list[EquipmentModel],
        processed: int,
        succeeded: int,
        failed: int,
        errors: list[str],
    ) -> None:
        if not batch:
            return
        with self._uow_factory() as uow:
            uow.session.add_all(batch)
            job = uow.session.get(ImportJob, job_id)
            if job is not None:
                job.processed_rows = processed
                job.succeeded = succeeded
                job.failed = failed
                job.errors = list(errors)

    def _finish(
        self, job_id: ImportJobId, status: ImportStatus, errors: list[str]
    ) -> ImportJob:
        with self._uow_factory() as uow:
            job = uow.session.get(ImportJob, job_id)
            if job is None:
                raise NotFound(f"задание {job_id} не найдено")
            job.status = status
            job.finished_at = self._clock.now()
            job.errors = list(errors)
            return job
