import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import vue from 'eslint-plugin-vue';

export default [
  { ignores: ['dist/**', '.cache/**', '.ai-rules/**', '.agents/**', '.local/**'] },
  { files: ['src/**/*.ts'], ...js.configs.recommended },
  ...tseslint.configs.recommended,
  ...vue.configs['flat/recommended'],
  { files: ['src/**/*.vue'], languageOptions: { parserOptions: { parser: tseslint.parser } } },
  // Optional example: apply only when pure calculations are a real boundary.
  {
    files: ['src/logic/**/*.ts'],
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [{
          group: ['vue', 'vue/**', '*.vue', '**/*.vue', '**/ui/**', '@/ui/**'],
          message: 'Pure logic must not import Vue or UI; pass values from the caller.'
        }]
      }],
      'no-restricted-syntax': ['error',
        { selector: 'ImportExpression', message: 'Keep dynamic loading outside pure logic.' },
        { selector: "CallExpression[callee.name='require']", message: 'Keep runtime loading outside pure logic.' }
      ]
    }
  }
];
