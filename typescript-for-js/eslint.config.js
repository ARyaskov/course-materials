import js from '@eslint/js';
import tseslint from 'typescript-eslint';

const NODE_GLOBALS = {
  process: 'readonly',
  console: 'readonly',
  Buffer: 'readonly',
  URL: 'readonly',
  URLSearchParams: 'readonly',
  fetch: 'readonly',
  require: 'readonly',
  module: 'writable',
  __filename: 'readonly',
  __dirname: 'readonly',
};

export default tseslint.config(
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**', 'public/board.js', 'public/board.js.map'],
  },

  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,

  {
    files: ['src/**/*.ts', 'tests/**/*.ts', 'types/**/*.ts'],
    languageOptions: {
      parserOptions: {
        // Два конфига: серверная часть и браузерная сборка доски.
        project: ['./tsconfig.json', './tsconfig.browser.json'],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Импорт типов отделён от импорта значений: так виден реальный граф зависимостей.
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'separate-type-imports' },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/switch-exhaustiveness-check': 'error',
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-console': ['warn', { allow: ['error'] }],
    },
  },

  {
    files: ['src/cli/**/*.ts', 'src/main.ts', 'scripts/**/*.js', 'legacy/**/*.js'],
    rules: { 'no-console': 'off' },
  },

  {
    // node:test возвращает промисы, которые по контракту не ожидают.
    files: ['tests/**/*.ts'],
    rules: { '@typescript-eslint/no-floating-promises': 'off' },
  },

  {
    files: ['legacy/**/*.js', 'scripts/**/*.js', 'scripts/**/*.cjs', 'eslint.config.js'],
    ...tseslint.configs.disableTypeChecked,
    languageOptions: {
      globals: NODE_GLOBALS,
      sourceType: 'module',
    },
  },
);
