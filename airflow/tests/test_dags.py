"""Проверки самих DAG-ов: импортируются без ошибок и имеют ожидаемую структуру.

Требуют установленного Airflow (запускать внутри контейнера или venv с зависимостями).
"""

from airflow.models import DagBag


def test_dags_import_without_errors():
    dag_bag = DagBag(include_examples=False)
    assert dag_bag.import_errors == {}, dag_bag.import_errors


def test_orders_dag_present_and_structured():
    dag = DagBag(include_examples=False).get_dag("orders__daily_etl")
    assert dag is not None
    expected = {"extract", "load_staging", "quality_gate_staging", "build_mart", "quality_gate_mart"}
    assert expected <= set(dag.task_ids)
