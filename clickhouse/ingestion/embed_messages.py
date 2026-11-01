"""Pulse: настоящие эмбеддинги сообщений открытой моделью (глава 16, необязательный шаг).

Читает уникальные сообщения из pulse.app_logs, вычисляет векторы моделью для предложений (384 измерения)
и вставляет в pulse.message_embeddings_384. Модель работает локально; логи наружу не отправляются.

  pip install sentence-transformers clickhouse-connect
  python embed_messages.py --days 3 [--model sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2]
"""

from __future__ import annotations

import argparse
import os

import clickhouse_connect


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--days', type=int, default=3)
    parser.add_argument('--model', default='sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2')
    parser.add_argument('--batch', type=int, default=256)
    args = parser.parse_args()

    from sentence_transformers import SentenceTransformer   # импорт здесь: библиотека тяжёлая и необязательная
    model = SentenceTransformer(args.model)

    client = clickhouse_connect.get_client(
        host=os.getenv('CLICKHOUSE_HOST', 'localhost'), port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
        username=os.getenv('CLICKHOUSE_USER', 'analyst'), password=os.getenv('CLICKHOUSE_PASSWORD', 'analyst'),
        database='pulse')

    rows = client.query(
        "SELECT cityHash64(msg) AS h, service, msg FROM ("
        "  SELECT service, normalizeQuery(lower(message)) AS msg FROM pulse.app_logs"
        f"  WHERE ts >= now() - INTERVAL {args.days} DAY) GROUP BY h, service, msg"
    ).result_rows
    print(f'unique messages: {len(rows)}')

    for start in range(0, len(rows), args.batch):
        chunk = rows[start:start + args.batch]
        vectors = model.encode([r[2] for r in chunk], normalize_embeddings=True)
        data = [[r[0], r[1], r[2], [float(x) for x in v]] for r, v in zip(chunk, vectors)]
        client.insert('message_embeddings_384', data, column_names=['message_hash', 'service', 'message', 'embedding'])
        print(f'inserted {start + len(chunk)}/{len(rows)}')


if __name__ == '__main__':
    main()
