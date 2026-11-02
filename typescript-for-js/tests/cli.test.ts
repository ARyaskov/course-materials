import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parseCliArgs, splitFlag } from '#cli/args.ts';
import { loadConfig, DEFAULT_CONFIG } from '#config/config.ts';
import { parseBoolean, parseEnum, parseNumber, requireString, MissingConfigError } from '#config/parse.ts';
import { run } from '#cli/run.ts';

describe('parseCliArgs', () => {
  it('по умолчанию выбирает status', () => {
    const parsed = parseCliArgs([]);

    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.value.command, 'status');
    assert.equal(parsed.value.limit, 20);
  });

  it('разбирает флаги', () => {
    const parsed = parseCliArgs(['status', '--env=production', '--status=failed', '--json']);

    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;

    assert.equal(parsed.value.environment, 'production');
    assert.equal(parsed.value.status, 'failed');
    assert.equal(parsed.value.json, true);
  });

  it('сообщает о неизвестной команде и неизвестном окружении', () => {
    assert.equal(parseCliArgs(['deploy']).ok, false);
    assert.equal(parseCliArgs(['status', '--env=prod']).ok, false);
    assert.equal(parseCliArgs(['status', '--limit=0']).ok, false);
    assert.equal(parseCliArgs(['status', '--limit=1000']).ok, false);
  });

  it('отклоняет неизвестный флаг', () => {
    assert.equal(parseCliArgs(['status', '--color']).ok, false);
  });

  it('разбирает строку вида --env=dev', () => {
    assert.deepEqual(splitFlag('--env=dev'), ['env', 'dev']);
    assert.equal(splitFlag('status'), null);
  });
});

describe('конфигурация', () => {
  it('использует значения по умолчанию для пустого окружения', () => {
    assert.deepEqual(loadConfig({}), DEFAULT_CONFIG);
  });

  it('читает переменные окружения', () => {
    const config = loadConfig({
      SHIPYARD_SOURCE: 'http',
      SHIPYARD_TIMEOUT_MS: '1500',
      SHIPYARD_LOG_LEVEL: 'debug',
      PORT: '9090',
    });

    assert.equal(config.source, 'http');
    assert.equal(config.timeoutMs, 1500);
    assert.equal(config.logLevel, 'debug');
    assert.equal(config.port, 9090);
  });

  it('игнорирует мусор вместо падения', () => {
    const config = loadConfig({ SHIPYARD_SOURCE: 'redis', SHIPYARD_TIMEOUT_MS: 'быстро' });

    assert.equal(config.source, DEFAULT_CONFIG.source);
    assert.equal(config.timeoutMs, DEFAULT_CONFIG.timeoutMs);
  });

  it('разбирает отдельные значения', () => {
    assert.equal(parseBoolean('yes', false), true);
    assert.equal(parseBoolean('нет', false), false);
    assert.equal(parseNumber(' 12 ', 0), 12);
    assert.equal(parseEnum('b', ['a', 'b'] as const, 'a'), 'b');
    assert.throws(() => requireString('  ', 'TOKEN'), MissingConfigError);
  });
});

describe('run', () => {
  function collect() {
    const out: string[] = [];
    const errors: string[] = [];

    return {
      io: { out: (text: string) => out.push(text), error: (text: string) => errors.push(text) },
      out,
      errors,
    };
  }

  it('печатает отчёт на фикстурах', async () => {
    const sink = collect();
    const code = await run({ argv: ['status', '--limit=3'], env: {}, io: sink.io });

    assert.equal(code, 0);
    assert.match(sink.out.join(''), /Shipyard/);
  });

  it('отдаёт JSON по флагу', async () => {
    const sink = collect();
    const code = await run({ argv: ['status', '--json', '--limit=2'], env: {}, io: sink.io });

    assert.equal(code, 0);

    const payload: unknown = JSON.parse(sink.out.join(''));
    assert.ok(typeof payload === 'object' && payload !== null && 'data' in payload);
  });

  it('возвращает код 2 при ошибке разбора аргументов', async () => {
    const sink = collect();
    const code = await run({ argv: ['status', '--env=прод'], env: {}, io: sink.io });

    assert.equal(code, 2);
    assert.match(sink.errors.join(''), /Неизвестное окружение/);
  });

  it('сообщает, что деплой не найден', async () => {
    const sink = collect();
    const code = await run({ argv: ['show', 'dep_999'], env: {}, io: sink.io });

    assert.equal(code, 1);
    assert.match(sink.errors.join(''), /не найден/);
  });

  it('показывает справку', async () => {
    const sink = collect();
    const code = await run({ argv: ['help'], env: {}, io: sink.io });

    assert.equal(code, 0);
    assert.match(sink.out.join(''), /Использование/);
  });
});
