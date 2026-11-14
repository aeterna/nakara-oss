import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: ['packages/*', 'apps/*'],
    exclude: ['**/dist/**', '**/node_modules/**'],
    testTimeout: 30000,
    hookTimeout: 30000,
  },
});
