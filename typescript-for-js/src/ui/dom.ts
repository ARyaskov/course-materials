/** Конструктор DOM-класса: нужен, чтобы проверить тип найденного элемента. */
export type ElementConstructor<T extends Element> = abstract new (...args: never[]) => T;

export class ElementNotFoundError extends Error {
  constructor(selector: string) {
    super(`Элемент не найден: ${selector}`);
    this.name = 'ElementNotFoundError';
  }
}

/**
 * querySelector возвращает Element | null и ничего не знает о конкретном теге.
 * Здесь мы один раз проверяем и селектор, и класс элемента.
 */
export function requireElement<T extends Element>(
  selector: string,
  constructor: ElementConstructor<T>,
  root: ParentNode = document,
): T {
  const found = root.querySelector(selector);
  if (found === null) throw new ElementNotFoundError(selector);

  if (!(found instanceof constructor)) {
    throw new TypeError(`Элемент ${selector} имеет неожиданный тип ${found.tagName}`);
  }

  return found;
}

export function findElement<T extends Element>(
  selector: string,
  constructor: ElementConstructor<T>,
  root: ParentNode = document,
): T | null {
  const found = root.querySelector(selector);
  return found instanceof constructor ? found : null;
}

export interface ElementOptions {
  readonly className?: string;
  readonly text?: string;
  readonly title?: string;
  readonly dataset?: Readonly<Record<string, string>>;
}

/** Создание элемента с типом, выведенным из имени тега. */
export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  options: ElementOptions = {},
  children: readonly Node[] = [],
): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);

  if (options.className !== undefined) element.className = options.className;
  if (options.text !== undefined) element.textContent = options.text;
  if (options.title !== undefined) element.title = options.title;

  for (const [key, value] of Object.entries(options.dataset ?? {})) {
    element.dataset[key] = value;
  }

  element.append(...children);

  return element;
}

export function clear(node: Element): void {
  node.replaceChildren();
}
