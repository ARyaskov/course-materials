"""Импорт каталога.

Долгая операция за коротким запросом: обработчик ставит задачу и сразу
возвращает 202 со ссылкой на ресурс состояния. Клиент опрашивает эту
ссылку, а не держит соединение открытым десять минут.
"""

from typing import Any
from uuid import UUID

from flask import g, jsonify, request, url_for

from depot.api.auth import call_context, requires
from depot.api.deps import import_service
from depot.api.docs.registry import document
from depot.api.v1 import bp
from depot.api.v1.schemas.rentals import ImportJobOut, ImportRequest
from depot.domain.enums import ImportStatus, Permission
from depot.domain.ids import ImportJobId
from depot.services.commands import ImportCatalogCommand

#: пока работа идёт, ответ не кешируется; завершённое задание уже
#: не изменится, и его можно подержать у клиента
IN_PROGRESS = frozenset({ImportStatus.QUEUED, ImportStatus.RUNNING})


@bp.post("/imports")
@requires(Permission.CATALOG_IMPORT)
@document(summary="Запуск импорта каталога", tags=["imports"], status=202)
def start_import() -> Any:
    payload = ImportRequest.model_validate(request.get_json())
    job = import_service().start(
        ImportCatalogCommand(user_id=g.actor.id, file_key=payload.file_key),
        ctx=call_context(),
    )
    location = url_for("v1.get_import", job_id=job.id)
    # 202 честно говорит: запрос принят, работа не выполнена
    return jsonify(ImportJobOut.model_validate(job).public()), 202, {"Location": location}


@bp.get("/imports/<uuid:job_id>")
@requires(Permission.CATALOG_IMPORT)
@document(summary="Состояние импорта", tags=["imports"])
def get_import(job_id: UUID) -> Any:
    job = import_service().get(ImportJobId(job_id), ctx=call_context())
    cache = "no-store" if job.status in IN_PROGRESS else "private, max-age=60"
    return jsonify(ImportJobOut.model_validate(job).public()), 200, {"Cache-Control": cache}
