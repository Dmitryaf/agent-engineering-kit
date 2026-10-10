import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  cacheDir: '.cache/vite',
  test: { environment: 'node', include: ['src/**/*.test.ts'] }
});
