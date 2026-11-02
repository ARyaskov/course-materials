import { describeApiError } from '#api/errors.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { renderReport, toRows } from '#reports/report.ts';
import type { ReportRow } from '#reports/report.ts';
import type { DeploymentService } from '#services/deployment-service.ts';

import type { CliOptions } from '../args.ts';
import { errorJson, printJson } from '../output/json.ts';
import { column, renderTable } from '../output/table.ts';
import type { Column } from '../output/table.ts';

export interface CommandIo {
  readonly out: (text: string) => void;
  readonly error: (text: string) => void;
}

const COLUMNS: readonly Column<ReportRow>[] = [
  column('ID', 'id'),
  column('Окружение', 'environment'),
  column('Статус', 'status'),
  column('Версия', 'version'),
  column('Коммит', 'commit'),
  column('Автор', 'author'),
  column('Начало', 'started'),
  column('Длительность', 'duration'),
];

export function queryFromOptions(options: CliOptions): DeploymentQuery {
  return {
    environment: options.environment,
    status: options.status,
    author: options.author,
    limit: options.limit,
    offset: 0,
  };
}

/** Возвращает код завершения процесса: 0 — успех, 1 — ошибка. */
export async function runStatus(
  service: DeploymentService,
  options: CliOptions,
  io: CommandIo,
): Promise<number> {
  const board = await service.board(queryFromOptions(options));

  if (!board.ok) {
    if (options.json) printJson(errorJson(describeApiError(board.error)), io.error);
    else io.error(`${describeApiError(board.error)}\n`);
    return 1;
  }

  if (options.json) {
    printJson(
      {
        data: toRows(board.value.deployments).map((row) => ({ ...row })),
        total: board.value.summary.total,
        successRate: board.value.summary.successRate,
      },
      io.out,
    );
    return 0;
  }

  io.out(`${renderReport(board.value.summary)}\n\n`);
  io.out(`${renderTable(toRows(board.value.deployments), COLUMNS)}\n`);

  return 0;
}

export async function runShow(
  service: DeploymentService,
  options: CliOptions,
  io: CommandIo,
): Promise<number> {
  const id = options.positional[0];

  if (id === undefined) {
    io.error('Укажите идентификатор: shipyard show dep_001\n');
    return 1;
  }

  const found = await service.find(id);

  if (!found.ok) {
    io.error(`${describeApiError(found.error)}\n`);
    return 1;
  }

  if (found.value === null) {
    io.error(`Деплой ${id} не найден\n`);
    return 1;
  }

  if (options.json) {
    printJson({ ...toRows([found.value])[0] }, io.out);
    return 0;
  }

  io.out(`${renderTable(toRows([found.value]), COLUMNS)}\n`);
  return 0;
}
