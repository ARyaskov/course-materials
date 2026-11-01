# Образ Airflow 3 с зависимостями проекта.
# Версию берите актуальную из ветки 3.x на момент сборки.
FROM apache/airflow:3.0.3

COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
