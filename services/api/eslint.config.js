import js from '@eslint/js';
import globals from 'globals';

export default [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: globals.node,
    },
    rules: {
      // Route handlers and middleware often have unused `next`/`req`
      // parameters that are still required by Express's signature -
      // flagging those isn't useful, so only flag genuinely unused vars.
      'no-unused-vars': ['warn', { argsIgnorePattern: '^(req|res|next|_)' }],
    },
  },
];
