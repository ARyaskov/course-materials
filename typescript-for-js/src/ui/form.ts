import { isDeploymentStatus } from '#domain/deployment-status.ts';
import { isEnvironment } from '#domain/environment.ts';

import type { BoardFilters } from './board-state.ts';

/**
 * FormData отдаёт string | File, поэтому значения формы проверяются
 * так же, как данные из сети.
 */
export function filtersFromForm(form: HTMLFormElement): BoardFilters {
  const data = new FormData(form);

  const environment = data.get('environment');
  const status = data.get('status');
  const author = data.get('author');

  return {
    environment: typeof environment === 'string' && isEnvironment(environment) ? environment : null,
    status: typeof status === 'string' && isDeploymentStatus(status) ? status : null,
    author: typeof author === 'string' ? author.trim() : '',
  };
}
