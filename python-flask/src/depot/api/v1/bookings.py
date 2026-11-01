"""Бронирование."""

from typing import Any
from uuid import UUID

from flask import g, jsonify, request

from depot.api.auth import call_context, requires
from depot.api.deps import booking_service
from depot.api.docs.registry import document
from depot.api.v1 import bp
from depot.api.v1.schemas.base import PageMeta, PageResponse
from depot.api.v1.schemas.bookings import (
    BookingCreate,
    BookingDetailOut,
    BookingOut,
    BookingQuery,
    BookingUpdate,
    CancelRequest,
)
from depot.domain.enums import Permission
from depot.domain.ids import BookingId
from depot.domain.period import Period
from depot.services.commands import (
    BookingFilters,
    CancelBookingCommand,
    ConfirmBookingCommand,
    CreateBookingCommand,
    UpdateBookingCommand,
)


@bp.post("/bookings")
@requires(Permission.BOOKING_CREATE)
@document(summary="Создание брони", tags=["bookings"], status=201)
def create_booking() -> Any:
    """Создание брони.

    Обработчик занимается только переводом: HTTP-запрос → команда,
    результат → HTTP-ответ. Пересечение периодов, удержание и цена —
    забота сервиса и базы.
    """
    payload = BookingCreate.model_validate(request.get_json())
    command = CreateBookingCommand(
        # владелец берётся из токена, а не из тела: иначе клиент оформит
        # бронь на чужой идентификатор
        user_id=g.actor.id,
        unit_id=payload.unit_id,
        # две даты схлопываются в доменный тип на границе: дальше по коду
        # рассогласовать начало и конец уже негде
        period=Period(payload.starts_at, payload.ends_at),
        note=payload.note or None,
        source="api",
    )
    booking = booking_service().create(command, ctx=call_context())
    body = BookingDetailOut.model_validate(booking).public()
    return jsonify(body), 201, {"Location": f"/api/v1/bookings/{booking.public_id}"}


@bp.get("/bookings")
@document(summary="Список броней", tags=["bookings"])
def list_bookings() -> Any:
    query = BookingQuery.model_validate(request.args.to_dict())
    page = booking_service().search(
        BookingFilters(
            status=query.status,
            station_id=query.station_id,
            unit_id=query.unit_id,
            starts_after=query.from_date,
            starts_before=query.to_date,
        ),
        ctx=call_context(),
        sort=query.sort,
        page=query.page,
        per_page=query.per_page,
    )
    body = PageResponse(
        items=[BookingOut.model_validate(item).public() for item in page.items],
        meta=PageMeta(total=page.total, page=page.page, per_page=page.per_page),
    )
    return jsonify(body.public())


@bp.get("/bookings/<uuid:booking_id>")
@document(summary="Карточка брони", tags=["bookings"])
def get_booking(booking_id: UUID) -> Any:
    # преобразователь uuid в правиле маршрута отсекает мусор до обработчика:
    # /bookings/abc даст 404, а не 500 из глубины репозитория
    booking = booking_service().get(BookingId(booking_id), ctx=call_context())
    return jsonify(BookingDetailOut.model_validate(booking).public())


@bp.patch("/bookings/<uuid:booking_id>")
@document(summary="Изменение брони", tags=["bookings"])
def update_booking(booking_id: UUID) -> Any:
    payload = BookingUpdate.model_validate(request.get_json())
    fields = payload.model_dump(exclude_unset=True)

    command = UpdateBookingCommand(booking_id=BookingId(booking_id))
    # период передаётся целиком либо не передаётся вовсе: сдвинуть одну
    # границу отдельным запросом нельзя — проверка пересечений выполняется
    # для пары значений
    if "starts_at" in fields and "ends_at" in fields:
        command = UpdateBookingCommand(
            booking_id=BookingId(booking_id),
            note=fields.get("note", command.note),
            period=Period(payload.starts_at, payload.ends_at),  # type: ignore[arg-type]
        )
    elif "note" in fields:
        command = UpdateBookingCommand(
            booking_id=BookingId(booking_id), note=fields["note"]
        )

    booking = booking_service().update(command, ctx=call_context())
    return jsonify(BookingDetailOut.model_validate(booking).public())


@bp.post("/bookings/<uuid:booking_id>/confirm")
@requires(Permission.BOOKING_CONFIRM)
@document(summary="Подтверждение брони", tags=["bookings"])
def confirm_booking(booking_id: UUID) -> Any:
    """Смена состояния — отдельный маршрут, а не PATCH статуса.

    Подтверждение снимает удержание, выставляет счёт и ставит уведомление
    в очередь. Спрятать это за присвоением поля значит сделать побочные
    эффекты незаметными в интерфейсе.
    """
    booking = booking_service().confirm(
        ConfirmBookingCommand(booking_id=BookingId(booking_id)),
        ctx=call_context(),
    )
    return jsonify(BookingDetailOut.model_validate(booking).public())


@bp.post("/bookings/<uuid:booking_id>/cancel")
@document(summary="Отмена брони", tags=["bookings"])
def cancel_booking(booking_id: UUID) -> Any:
    payload = CancelRequest.model_validate(request.get_json(silent=True) or {})
    booking = booking_service().cancel(
        CancelBookingCommand(booking_id=BookingId(booking_id), reason=payload.reason or None),
        ctx=call_context(),
    )
    return jsonify(BookingDetailOut.model_validate(booking).public())
