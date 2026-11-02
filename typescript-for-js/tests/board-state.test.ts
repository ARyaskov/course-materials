import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { fixtureDeployments } from '#fixtures/deployments.ts';
import { summarize } from '#reports/summary.ts';
import { boardReducer, initialBoardState, selectedDeployment } from '#ui/board-state.ts';
import type { BoardData } from '#ui/board-state.ts';
import { createBoardStore } from '#ui/store.ts';
import { describeFilters, requestFromFilters } from '#ui/filters.ts';

const DATA: BoardData = {
  deployments: fixtureDeployments,
  summary: summarize(fixtureDeployments),
};

describe('boardReducer', () => {
  it('переходит из idle в loading и ready', () => {
    const loading = boardReducer(initialBoardState, { type: 'load' });
    assert.equal(loading.view.kind, 'loading');

    const ready = boardReducer(loading, { type: 'loaded', data: DATA });
    assert.equal(ready.view.kind, 'ready');
  });

  it('сохраняет сообщение об ошибке', () => {
    const failed = boardReducer(initialBoardState, { type: 'failed', message: 'нет сети' });

    assert.equal(failed.view.kind, 'error');
    if (failed.view.kind !== 'error') return;
    assert.equal(failed.view.message, 'нет сети');
  });

  it('сбрасывает выбор при смене фильтров', () => {
    const ready = boardReducer(initialBoardState, { type: 'loaded', data: DATA });
    const selected = boardReducer(ready, { type: 'select', id: 'dep_001' });
    const filtered = boardReducer(selected, { type: 'filters', patch: { environment: 'dev' } });

    assert.equal(selected.selectedId, 'dep_001');
    assert.equal(filtered.selectedId, null);
    assert.equal(filtered.filters.environment, 'dev');
  });

  it('находит выбранный деплой только в состоянии ready', () => {
    const ready = boardReducer(initialBoardState, { type: 'loaded', data: DATA });
    const selected = boardReducer(ready, { type: 'select', id: 'dep_003' });

    assert.equal(selectedDeployment(selected)?.status, 'rolled_back');
    assert.equal(selectedDeployment(initialBoardState), null);
  });

  it('возвращается в начальное состояние', () => {
    const ready = boardReducer(initialBoardState, { type: 'loaded', data: DATA });
    assert.deepEqual(boardReducer(ready, { type: 'reset' }), initialBoardState);
  });
});

describe('store', () => {
  it('уведомляет подписчиков об изменениях', () => {
    const store = createBoardStore();
    const seen: string[] = [];

    const unsubscribe = store.subscribe((state) => seen.push(state.view.kind));

    store.dispatch({ type: 'load' });
    store.dispatch({ type: 'loaded', data: DATA });
    unsubscribe();
    store.dispatch({ type: 'reset' });

    assert.deepEqual(seen, ['loading', 'ready']);
    assert.equal(store.state.view.kind, 'idle');
  });
});

describe('фильтры', () => {
  it('не отправляет пустые параметры', () => {
    const request = requestFromFilters(
      { environment: null, status: 'failed', author: '' },
      25,
    );

    assert.deepEqual(request, { status: 'failed', limit: 25 });
  });

  it('описывает выбранные фильтры', () => {
    assert.equal(describeFilters({ environment: null, status: null, author: '' }), 'без фильтров');
    assert.equal(
      describeFilters({ environment: 'dev', status: null, author: 'anna' }),
      'окружение: dev, автор: anna',
    );
  });
});
