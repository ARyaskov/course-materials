import type { Deployment } from '#domain/deployment.ts';
import { durationOf, startedOrQueuedAt } from '#domain/deployment.ts';
import { statusTitle } from '#domain/deployment-status.ts';
import { environmentTitle } from '#domain/environment.ts';
import { shortSha } from '#domain/release.ts';
import { assertNever } from '#lib/assert-never.ts';
import { formatDateTime, formatDuration, formatPercent } from '#lib/format.ts';
import type { DeploymentSummary } from '#reports/summary.ts';

import type { BoardState } from './board-state.ts';
import { describeFilters } from './filters.ts';
import { clear, el } from './dom.ts';

function renderCard(deployment: Deployment, selected: boolean): HTMLElement {
  const badge = el('span', {
    className: `badge badge--${deployment.status}`,
    text: statusTitle(deployment.status),
  });

  const title = el('div', { className: 'card__title' }, [
    el('strong', { text: deployment.release.version }),
    badge,
  ]);

  const meta = el('dl', { className: 'card__meta' }, [
    el('dt', { text: 'Окружение' }),
    el('dd', { text: environmentTitle(deployment.environment) }),
    el('dt', { text: 'Коммит' }),
    el('dd', { text: shortSha(deployment.release) }),
    el('dt', { text: 'Инициатор' }),
    el('dd', { text: deployment.requestedBy }),
    el('dt', { text: 'Начало' }),
    el('dd', { text: formatDateTime(startedOrQueuedAt(deployment)) }),
    el('dt', { text: 'Длительность' }),
    el('dd', { text: formatDuration(durationOf(deployment)) }),
  ]);

  const details = renderDetails(deployment);

  return el(
    'article',
    {
      className: selected ? 'card card--selected' : 'card',
      dataset: { id: deployment.id },
    },
    details === null ? [title, meta] : [title, meta, details],
  );
}

/** Дополнительные поля есть не у всех вариантов — их даёт сужение по статусу. */
function renderDetails(deployment: Deployment): HTMLElement | null {
  switch (deployment.status) {
    case 'failed':
      return el('p', {
        className: 'card__note card__note--error',
        text: `Ошибка (код ${deployment.exitCode}): ${deployment.reason}`,
      });

    case 'rolled_back':
      return el('p', {
        className: 'card__note',
        text: `Откат к релизу ${deployment.revertedTo}`,
      });

    case 'queued':
      return el('p', { className: 'card__note', text: 'Ожидает запуска' });

    case 'running':
      return el('p', { className: 'card__note', text: 'Выполняется прямо сейчас' });

    case 'succeeded':
      return deployment.comment === null
        ? null
        : el('p', { className: 'card__note', text: deployment.comment });

    default:
      return assertNever(deployment, 'renderDetails');
  }
}

function renderSummary(summary: DeploymentSummary): HTMLElement {
  const cells = summary.environments
    .filter((environment) => environment.total > 0)
    .map((environment) =>
      el('li', {
        text:
          `${environmentTitle(environment.environment)}: ${environment.total} — ` +
          `успешных ${formatPercent(environment.successRate)}, ` +
          `среднее ${formatDuration(environment.averageDurationMs)}`,
      }),
    );

  return el('section', { className: 'summary' }, [
    el('h2', { text: `Всего деплоев: ${summary.total}` }),
    el('ul', {}, cells),
  ]);
}

function renderMessage(text: string, modifier: string): HTMLElement {
  return el('p', { className: `message message--${modifier}`, text });
}

/** Одна функция отрисовки на всё состояние: экран всегда соответствует данным. */
export function renderBoard(root: HTMLElement, state: BoardState): void {
  clear(root);

  switch (state.view.kind) {
    case 'idle':
      root.append(renderMessage('Выберите фильтры и нажмите «Обновить»', 'idle'));
      return;

    case 'loading':
      root.append(renderMessage('Загружаем деплои…', 'loading'));
      return;

    case 'error':
      root.append(renderMessage(state.view.message, 'error'));
      return;

    case 'ready': {
      const { deployments, summary } = state.view.data;

      root.append(renderSummary(summary));
      root.append(
        el('p', { className: 'filters-note', text: describeFilters(state.filters) }),
      );

      if (deployments.length === 0) {
        root.append(renderMessage('Под фильтры ничего не подошло', 'empty'));
        return;
      }

      root.append(
        el(
          'div',
          { className: 'cards' },
          deployments.map((deployment) =>
            renderCard(deployment, deployment.id === state.selectedId),
          ),
        ),
      );
      return;
    }

    default:
      assertNever(state.view, 'renderBoard');
  }
}
