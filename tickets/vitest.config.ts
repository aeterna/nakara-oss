import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      {
        extends: true,
        test: {
          name: 'packages/core',
          root: 'packages/core',
        },
      },
      {
        extends: true,
        test: {
          name: 'packages/db',
          root: 'packages/db',
        },
      },
      {
        extends: true,
        test: {
          name: 'packages/discord',
          root: 'packages/discord',
        },
      },
      {
        extends: true,
        test: {
          name: 'apps/server',
          root: 'apps/server',
        },
      },
      'apps/web',
    ],
    exclude: ['**/dist/**', '**/node_modules/**'],
    testTimeout: 30000,
    hookTimeout: 60000,
  },
});
