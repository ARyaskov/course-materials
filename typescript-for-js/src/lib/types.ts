/** Разворачивает агрегированный тип для читаемых подсказок редактора. */
export type Expand<T> = T extends infer O ? { [K in keyof O]: O[K] } : never;

/** `Omit`, который ловит опечатку в имени поля. */
export type StrictOmit<T, K extends keyof T> = Omit<T, K>;

/** Снимает `readonly` со всех полей. */
export type Mutable<T> = { -readonly [K in keyof T]: T[K] };

/** Ключи, значения которых совместимы с `V`. */
export type KeysOfType<T, V> = {
  [K in keyof T]-?: T[K] extends V ? K : never;
}[keyof T];

/** `Omit`, применённый к каждому варианту объединения. */
export type DistributiveOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never;

/** Тип элемента массива. */
export type ElementOf<T> = T extends readonly (infer E)[] ? E : never;

/** Тип значения успешного результата. */
export type UnwrapResult<T> = T extends { readonly ok: true; readonly value: infer V } ? V : never;
