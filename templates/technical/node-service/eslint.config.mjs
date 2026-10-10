import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import { builtinModules } from 'node:module';

export default [
  { ignores: ['dist/**', '.ai-rules/**', '.agents/**', '.local/**'] },
  { files: ['src/**/*.ts'], ...js.configs.recommended },
  ...tseslint.configs.recommended,
  // Optional example: pure decisions do not own HTTP or filesystem effects.
  {
    files: ['src/logic/**/*.ts'],
    ignores: ['**/*.test.ts'],
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [{
          group: ['node:*', ...builtinModules, '**/adapters/**', '**/server.js'],
          message: 'Pure logic must not import platform adapters; pass data from the caller.'
        }]
      }],
      'no-restricted-syntax': ['error',
        { selector: 'ImportExpression', message: 'Keep dynamic loading outside pure logic.' },
        { selector: "CallExpression[callee.name='require']", message: 'Keep runtime loading outside pure logic.' }
      ]
    }
  }
];
