"""Выдача и возврат оборудования."""

from typing import Any
from uuid import UUID

from flask import current_app, jsonify, request

from depot.api.auth import call_context, requires
from depot.api.deps import rental_service
from depot.api.docs.registry import document
from depot.api.v1 import bp
from depot.api.v1.schemas.base import PageMeta, PageResponse
from depot.api.v1.schemas.rentals import (
    IssueRequest,
    RentalOut,
    RentalQuery,
    ReturnRequest,
)
from depot.domain.enums import Permission
from depot.domain.errors import PayloadTooLarge, ValidationError
from depot.domain.ids import BookingId, RentalId
from depot.infrastructure.storage import detect_image_type, read_limited
from depot.services.commands import IssueRentalCommand, ReturnRentalCommand


@bp.post("/rentals")
@requires(Permission.RENTAL_ISSUE)
@document(summary="Выдача по брони", tags=["rentals"], status=201)
def issue_rental() -> Any:
    payload = IssueRequest.model_validate(request.get_json())
    if not payload.checklist_ok:
        # осмотр перед выдачей — часть операции, а не формальность:
        # без него спорное повреждение нечем закрыть
        raise ValidationError("Осмотр перед выдачей не подтверждён")

    rental = rental_service().issue(
        IssueRentalCommand(booking_id=BookingId(payload.booking_id)),
        ctx=call_context(),
    )
    body = RentalOut.model_validate(rental).public()
    return jsonify(body), 201, {"Location": f"/api/v1/rentals/{rental.id}"}


@bp.get("/rentals")
@document(summary="Список выдач", tags=["rentals"])
def list_rentals() -> Any:
    query = RentalQuery.model_validate(request.args.to_dict())
    page = rental_service().search(
        ctx=call_context(),
        overdue_only=query.overdue_only,
        page=query.page,
        per_page=query.per_page,
    )
    body = PageResponse(
        items=[RentalOut.model_validate(item).public() for item in page.items],
        meta=PageMeta(total=page.total, page=page.page, per_page=page.per_page),
    )
    return jsonify(body.public())


@bp.get("/rentals/<uuid:rental_id>")
@document(summary="Карточка выдачи", tags=["rentals"])
def get_rental(rental_id: UUID) -> Any:
    rental = rental_service().get(RentalId(rental_id), ctx=call_context())
    return jsonify(RentalOut.model_validate(rental).public())


@bp.post("/rentals/<uuid:rental_id>/return")
@requires(Permission.RENTAL_RETURN)
@document(summary="Приём оборудования", tags=["rentals"])
def return_rental(rental_id: UUID) -> Any:
    """Возврат.

    Здесь сходятся три следствия: состояние единицы, счёт за просрочку
    и акт повреждений. Все три оформляются одной транзакцией в сервисе —
    иначе возможен возврат без счёта или счёт без возврата.
    """
    payload = ReturnRequest.model_validate(request.get_json())
    result = rental_service().accept_return(
        ReturnRentalCommand(
            rental_id=RentalId(rental_id),
            condition=payload.condition,
            damage_description=payload.damage_description,
            damage_cost=payload.damage_cost,
        ),
        ctx=call_context(),
    )
    return jsonify(
        {
            "rental": RentalOut.model_validate(result.rental).public(),
            "late_fee": str(result.late_fee_amount),
            "damage_report_id": (
                str(result.damage_report_id) if result.damage_report_id else None
            ),
        }
    )


@bp.post("/rentals/<uuid:rental_id>/photos")
@requires(Permission.RENTAL_RETURN)
@document(summary="Загрузка фотографии повреждения", tags=["rentals"], status=201)
def upload_photo(rental_id: UUID) -> Any:
    """Приём файла.

    Расширение и заголовок Content-Type приходят от клиента и ничего
    не доказывают: тип определяется по сигнатуре первых байтов, а размер
    ограничивается при чтении, а не после него.
    """
    upload = request.files.get("file")
    if upload is None:
        raise ValidationError("Ожидается поле file в multipart/form-data")

    limit = int(current_app.config["MAX_FILE_SIZE"])
    try:
        data = read_limited(upload.stream, limit)
    except ValueError:
        raise PayloadTooLarge(f"Файл больше {limit // 1024 // 1024} МБ") from None

    # определение по сигнатуре, а не по расширению и не по Content-Type:
    # оба приходят от клиента и ничего не гарантируют
    media_type = detect_image_type(data)

    key = rental_service().store_photo(
        RentalId(rental_id),
        data=data,
        media_type=media_type,
        original_name=upload.filename or "photo",
        ctx=call_context(),
    )
    return jsonify({"key": key, "content_type": media_type}), 201
