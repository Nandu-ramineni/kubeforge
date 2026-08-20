import js from '@eslint/js';
import globals from 'globals';

export default [
  js.configs.recommended,
  {
    files: ['src/**/*.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: globals.node,
    },
  },
  {
    files: ['test/**/*.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: globals.node,
    },
  },
  {
    // public/app.js runs in the browser via a plain <script src>, not as an
    // ES module - different globals (window, fetch, document) and a
    // different sourceType than the Node-side server code above.
    files: ['public/**/*.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'script',
      globals: globals.browser,
    },
  },
];
