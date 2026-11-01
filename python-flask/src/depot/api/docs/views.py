"""Отдача документа и страницы просмотра.

Blueprint регистрируется только когда DOCS_ENABLED истинно: описание
внутренних маршрутов — это карта поверхности атаки, и в открытом контуре
она обычно закрыта.
"""

from typing import Any

from flask import Blueprint, Response, current_app, jsonify

bp = Blueprint("docs", __name__)

#: страница просмотра берётся с CDN и подгружает документ по относительному
#: пути: своей копии интерфейса в репозитории не нужно
_VIEWER = """<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <title>Depot API</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>body { margin: 0 }</style>
</head>
<body>
  <div id="app"></div>
  <script src="https://cdn.jsdelivr.net/npm/redoc@2/bundles/redoc.standalone.js"></script>
  <script>
    Redoc.init('openapi.json', {}, document.getElementById('app'));
  </script>
</body>
</html>
"""


@bp.get("/openapi.json")
def openapi() -> Any:
    # документ собран один раз при старте: пересобирать его на каждый
    # запрос незачем, таблица маршрутов после старта не меняется
    return jsonify(current_app.extensions["openapi"])


@bp.get("/docs")
def viewer() -> Response:
    return Response(_VIEWER, mimetype="text/html")
