/** Пауза с поддержкой отмены; работает и в Node, и в браузере. */
export function delay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted === true) {
      reject(signal.reason as Error);
      return;
    }

    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);

    function onAbort(): void {
      clearTimeout(timer);
      reject(signal?.reason as Error);
    }

    signal?.addEventListener('abort', onAbort, { once: true });
  });
}
