"""Pulse: симулятор backend-приложения, отправляющего события (глава 6).

Показывает правильный паттерн загрузки из приложения:
  - обработчик кладёт событие в буфер и не ждёт базу;
  - фоновый поток сбрасывает буфер по двум порогам (строки / секунды);
  - каждый пакет несёт токен идемпотентности и повторяется с экспоненциальной паузой;
  - при исчерпании попыток пакет уходит на диск (spill/), а не теряется;
  - при остановке буфер сбрасывается до выхода.

Запуск:
  python emit_events.py --rate 500 --seconds 60            # типизированные события → pulse.events_in
  python emit_events.py --rate 500 --seconds 60 --kafka    # JSON-события → тема pulse.events

Подключение задаётся переменными окружения:
  CLICKHOUSE_HOST (localhost), CLICKHOUSE_PORT (8123), CLICKHOUSE_USER (analyst),
  CLICKHOUSE_PASSWORD (analyst), KAFKA_BOOTSTRAP (localhost:9092),
  PULSE_INSERT_TABLE (events_in; для кластера — events_in_dist)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import random
import signal
import threading
import time
import uuid
from decimal import Decimal
from pathlib import Path

COLUMNS = ['event_time', 'user_id', 'session_id', 'event_type',
           'country', 'device', 'endpoint', 'status', 'amount', 'attributes']

EVENT_TYPES = ['view'] * 60 + ['click'] * 30 + ['purchase'] * 5 + ['error'] * 5
COUNTRIES = ['DE', 'FR', 'US', 'GB', 'PL']
DEVICES = ['web', 'ios', 'android']
ENDPOINTS = ['/home', '/pricing', '/checkout', '/api/v1/orders', '/api/v1/orders/{id}', '/api/v1/users/{id}']
PLANS = {'9.90': 'basic', '19.90': 'pro', '49.00': 'team'}
SPILL_DIR = Path(__file__).resolve().parent / 'spill'


def make_event() -> dict:
    """Одно синтетическое событие в виде словаря (глава 7: атрибуты latency_ms и plan)."""
    event_type = random.choice(EVENT_TYPES)
    endpoint = '/checkout' if event_type == 'purchase' else random.choice(ENDPOINTS)
    endpoint = endpoint.replace('{id}', str(random.randint(1000, 99999)))   # сырой адрес с идентификатором
    attributes: dict[str, str] = {}
    if endpoint.startswith('/api/'):
        # длительность запроса: длинный хвост, ошибки медленнее
        base = random.expovariate(1 / 120)
        attributes['latency_ms'] = str(int(base * (4 if event_type == 'error' else 1)) + 5)
    price = random.choice(list(PLANS)) if event_type == 'purchase' else None
    if price:
        attributes['plan'] = PLANS[price]
    return {
        'event_time': dt.datetime.now(dt.timezone.utc).replace(microsecond=0),
        'user_id': random.randint(1, 1000),
        'session_id': uuid.uuid4(),
        'event_type': event_type,
        'country': random.choice(COUNTRIES),
        'device': random.choice(DEVICES),
        'endpoint': endpoint,
        'status': 500 if event_type == 'error' else 200,
        'amount': Decimal(price) if price else None,
        'attributes': attributes,
    }


class Sink:
    """Куда уходит пакет: ClickHouse (типизированно) или Kafka (JSON)."""

    def send(self, batch: list[dict], token: str) -> None:
        raise NotImplementedError


class ClickHouseSink(Sink):
    def __init__(self) -> None:
        import clickhouse_connect
        self.client = clickhouse_connect.get_client(
            host=os.getenv('CLICKHOUSE_HOST', 'localhost'),
            port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
            username=os.getenv('CLICKHOUSE_USER', 'analyst'),
            password=os.getenv('CLICKHOUSE_PASSWORD', 'analyst'),
            database='pulse',
            compress=True,
        )

    def send(self, batch: list[dict], token: str) -> None:
        rows = [[e[c] for c in COLUMNS] for e in batch]
        # PULSE_INSERT_TABLE=events_in_dist — для кластера (глава 13)
        self.client.insert(os.getenv('PULSE_INSERT_TABLE', 'events_in'), rows, column_names=COLUMNS,
                           settings={'insert_deduplication_token': token})


class KafkaSink(Sink):
    def __init__(self, topic: str = 'pulse.events') -> None:
        from confluent_kafka import Producer
        self.topic = topic
        self.producer = Producer({
            'bootstrap.servers': os.getenv('KAFKA_BOOTSTRAP', 'localhost:9092'),
            'enable.idempotence': True,
            'linger.ms': 50,
        })

    def send(self, batch: list[dict], token: str) -> None:
        for e in batch:
            self.producer.produce(self.topic, value=to_json(e), key=str(e['user_id']))
        self.producer.flush(timeout=10)


def to_json(e: dict) -> str:
    out = dict(e)
    out['event_time'] = e['event_time'].strftime('%Y-%m-%dT%H:%M:%SZ')
    out['session_id'] = str(e['session_id'])
    if e['amount'] is None:
        del out['amount']
    else:
        out['amount'] = str(e['amount'])
    return json.dumps(out, ensure_ascii=False)


class EventBuffer:
    """Буфер с двумя порогами сброса и фоновой отправкой."""

    def __init__(self, sink: Sink, max_rows: int = 10_000, max_seconds: float = 1.0) -> None:
        self.sink = sink
        self.max_rows, self.max_seconds = max_rows, max_seconds
        self.rows: list[dict] = []
        self.lock = threading.Lock()
        self.last_flush = time.monotonic()
        self.stopping = threading.Event()
        self.stats = {'batches': 0, 'rows': 0, 'retries': 0, 'spilled': 0}
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def add(self, event: dict) -> None:
        with self.lock:
            self.rows.append(event)

    def _take(self, force: bool = False) -> list[dict]:
        with self.lock:
            due = force or len(self.rows) >= self.max_rows or \
                time.monotonic() - self.last_flush >= self.max_seconds
            if not due or not self.rows:
                return []
            batch, self.rows = self.rows, []
            self.last_flush = time.monotonic()
            return batch

    def _loop(self) -> None:
        while not self.stopping.is_set():
            time.sleep(0.1)
            batch = self._take()
            if batch:
                self._flush(batch)

    def _flush(self, batch: list[dict]) -> None:
        token = f'pulse-{uuid.uuid4()}'          # один токен на все попытки пакета
        for attempt in range(5):
            try:
                self.sink.send(batch, token)
                self.stats['batches'] += 1
                self.stats['rows'] += len(batch)
                return
            except Exception as exc:                # noqa: BLE001 — любой отказ транспорта
                self.stats['retries'] += 1
                print(f'flush failed (attempt {attempt + 1}): {exc}')
                time.sleep(2 ** attempt)
        self._spill(batch)

    def _spill(self, batch: list[dict]) -> None:
        SPILL_DIR.mkdir(exist_ok=True)
        name = SPILL_DIR / f"events-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%S}.jsonl"
        with open(name, 'a', encoding='utf-8') as f:
            for e in batch:
                f.write(to_json(e) + '\n')
        self.stats['spilled'] += len(batch)
        print(f'spilled {len(batch)} rows to {name}')

    def flush_now(self) -> None:
        """Финальный сброс при остановке."""
        self.stopping.set()
        self.thread.join(timeout=5)
        batch = self._take(force=True)
        if batch:
            self._flush(batch)


def main() -> None:
    parser = argparse.ArgumentParser(description='Pulse event emitter')
    parser.add_argument('--rate', type=int, default=200, help='событий в секунду')
    parser.add_argument('--seconds', type=int, default=30, help='длительность, с')
    parser.add_argument('--kafka', action='store_true', help='писать в Kafka вместо ClickHouse')
    parser.add_argument('--max-rows', type=int, default=10_000)
    parser.add_argument('--max-seconds', type=float, default=1.0)
    args = parser.parse_args()

    sink = KafkaSink() if args.kafka else ClickHouseSink()
    buffer = EventBuffer(sink, args.max_rows, args.max_seconds)

    def stop(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)

    started = time.monotonic()
    try:
        while time.monotonic() - started < args.seconds:
            tick = time.monotonic()
            for _ in range(args.rate):
                buffer.add(make_event())       # так вызывал бы обработчик запроса
            time.sleep(max(0.0, 1.0 - (time.monotonic() - tick)))
    except KeyboardInterrupt:
        pass
    finally:
        buffer.flush_now()
        print('stats:', buffer.stats)


if __name__ == '__main__':
    main()
