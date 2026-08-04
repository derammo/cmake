// eslint flat config
// this file was generated via `make -f ../../cmake/setup.make typescript`
import tseslint from "typescript-eslint";

export default tseslint.config(
	{ ignores: ["dist/"] },
	...tseslint.configs.recommended,
	{
    rules: {
      complexity: ['warn', 12],
      'max-lines': ['warn', { max: 200, skipBlankLines: true, skipComments: true }],
      'max-lines-per-function': ['warn', { max: 50, skipBlankLines: true, skipComments: true }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-restricted-syntax': ['error',
        { selector: 'TSImportType', message: 'Use a top-level import instead of inline import() type expressions.' },
        { selector: 'ImportDeclaration[importKind="type"]:has(ImportSpecifier)', message: 'Use import { type Foo } instead of import type { Foo }.' },
      ],
    },
  },
  {
    files: ['**/*.test.ts', '**/*.vscodetest.ts', '**/test/**/*.ts', '**/vscodetest/**/*.ts'],
    rules: {
      'max-lines': 'off',
      'max-lines-per-function': 'off',
      '@typescript-eslint/no-explicit-any': 'off',
      'no-restricted-globals': ['error',
        { name: 'setTimeout', message: 'Use proper async signaling (callbacks, events, promises) instead of setTimeout.' },
      ],
    },
  },
	{
	  languageOptions: {
			parserOptions: {
				tsconfigRootDir: import.meta.dirname,
			},
		},
  },
);
