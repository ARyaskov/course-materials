"""Каталог оборудования и точки выдачи."""

from typing import Any

from flask import g, jsonify, request

from depot.api.auth import anonymous_context, call_context, requires
from depot.api.deps import catalog_service
from depot.api.docs.registry import document
from depot.api.v1 import bp
from depot.api.v1.schemas.base import PageMeta, PageResponse
from depot.api.v1.schemas.catalog import (
    CatalogQuery,
    ModelCreate,
    ModelDetailOut,
    ModelOut,
    ModelUpdate,
    StationOut,
    UnitOut,
)
from depot.domain.enums import Permission
from depot.domain.ids import ModelId, StationId
from depot.services.commands import CatalogFilters, CreateModelCommand


def _context() -> Any:
    """Контекст вызова для маршрутов с необязательным токеном."""
    return call_context() if g.get("actor") else anonymous_context()


@bp.get("/models")
@document(summary="Список моделей оборудования", tags=["catalog"], public=True)
def list_models() -> Any:
    query = CatalogQuery.model_validate(request.args.to_dict())
    page = catalog_service().search(
        CatalogFilters(
            category=query.category,
            station_id=StationId(query.station_id) if query.station_id else None,
            min_rate=query.min_rate,
            max_rate=query.max_rate,
            query=query.q,
            available_from=query.available_from,
            available_to=query.available_to,
        ),
        ctx=_context(),
        sort=query.sort,
        page=query.page,
        per_page=query.per_page,
    )
    body = PageResponse(
        items=[ModelOut.model_validate(item).public() for item in page.items],
        meta=PageMeta(total=page.total, page=page.page, per_page=page.per_page),
    )
    # каталог меняется редко: короткий кеш у клиента снимает основную часть
    # повторных запросов со списка
    return jsonify(body.public()), 200, {"Cache-Control": "public, max-age=60"}


@bp.get("/models/<int:model_id>")
@document(summary="Карточка модели", tags=["catalog"], public=True)
def get_model(model_id: int) -> Any:
    model = catalog_service().get(ModelId(model_id), ctx=_context())
    return jsonify(ModelDetailOut.model_validate(model).public())


@bp.post("/models")
@requires(Permission.CATALOG_WRITE)
@document(summary="Создание модели", tags=["catalog"], status=201)
def create_model() -> Any:
    payload = ModelCreate.model_validate(request.get_json())
    model = catalog_service().create(
        CreateModelCommand(**payload.model_dump()),
        ctx=call_context(),
    )
    body = ModelDetailOut.model_validate(model).public()
    # Location указывает на созданный ресурс: клиенту не нужно собирать
    # путь самостоятельно
    return jsonify(body), 201, {"Location": f"/api/v1/models/{model.id}"}


@bp.patch("/models/<int:model_id>")
@requires(Permission.CATALOG_WRITE)
@document(summary="Изменение модели", tags=["catalog"])
def update_model(model_id: int) -> Any:
    payload = ModelUpdate.model_validate(request.get_json())
    # exclude_unset отделяет «поле не передано» от «передано null»:
    # без него частичное обновление обнуляет всё, что клиент не прислал
    changes = payload.model_dump(exclude_unset=True)
    model = catalog_service().update(ModelId(model_id), changes, ctx=call_context())
    return jsonify(ModelDetailOut.model_validate(model).public())


@bp.get("/stations")
@document(summary="Точки выдачи", tags=["catalog"], public=True)
def list_stations() -> Any:
    stations = catalog_service().stations(ctx=_context())
    return jsonify(
        {"items": [StationOut.model_validate(s).public() for s in stations]}
    )


@bp.get("/stations/<int:station_id>/units")
@requires(Permission.CATALOG_WRITE)
@document(summary="Парк точки выдачи", tags=["catalog"])
def list_units(station_id: int) -> Any:
    units = catalog_service().units_of(StationId(station_id), ctx=call_context())
    return jsonify({"items": [UnitOut.model_validate(u).public() for u in units]})
