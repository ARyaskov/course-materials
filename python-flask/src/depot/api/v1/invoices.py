"""Счета."""

from typing import Any
from uuid import UUID

from flask import jsonify, request

from depot.api.auth import call_context, requires
from depot.api.deps import billing_service
from depot.api.docs.registry import document
from depot.api.v1 import bp
from depot.api.v1.schemas.base import InputSchema, PageMeta, PageResponse
from depot.api.v1.schemas.rentals import InvoiceOut
from depot.api.v1.schemas.types import Page, PerPage
from depot.domain.enums import Permission
from depot.domain.ids import InvoiceId

# схемы объявлены рядом с единственным разделом, который их использует:
# выносить в общий модуль две строки означает разнести связанное по файлам


class InvoiceQuery(InputSchema):
    page: Page = 1
    per_page: PerPage = 20


class VoidRequest(InputSchema):
    reason: str = ""


@bp.get("/invoices")
@document(summary="Список счетов", tags=["billing"])
def list_invoices() -> Any:
    query = InvoiceQuery.model_validate(request.args.to_dict())
    page = billing_service().search(
        ctx=call_context(), page=query.page, per_page=query.per_page
    )
    body = PageResponse(
        items=[InvoiceOut.model_validate(item).public() for item in page.items],
        meta=PageMeta(total=page.total, page=page.page, per_page=page.per_page),
    )
    return jsonify(body.public())


@bp.get("/invoices/<uuid:invoice_id>")
@document(summary="Счёт", tags=["billing"])
def get_invoice(invoice_id: UUID) -> Any:
    invoice = billing_service().get(InvoiceId(invoice_id), ctx=call_context())
    return jsonify(InvoiceOut.model_validate(invoice).public())


@bp.post("/invoices/<uuid:invoice_id>/void")
@requires(Permission.INVOICE_VOID)
@document(summary="Аннулирование счёта", tags=["billing"])
def void_invoice(invoice_id: UUID) -> Any:
    """Аннулирование, а не удаление.

    Финансовый документ не исчезает: он получает статус и остаётся
    в истории. Иначе сумма выручки за прошлый месяц меняется задним числом.
    """
    payload = VoidRequest.model_validate(request.get_json(silent=True) or {})
    invoice = billing_service().void(
        InvoiceId(invoice_id), reason=payload.reason[:300], ctx=call_context()
    )
    return jsonify(InvoiceOut.model_validate(invoice).public())
