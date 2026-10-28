import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    include: ['src/**/*.test.{ts,tsx}', 'worker/**/*.test.ts', 'supabase/functions/**/*.test.ts'],
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json-summary', 'html'],
      include: ['src/**/*.{ts,tsx}', 'worker/**/*.ts'],
      exclude: ['src/test/**', 'src/main.tsx', 'src/vite-env.d.ts', '**/*.test.{ts,tsx}'],
      thresholds: {
        statements: 50,
        branches: 45,
        functions: 48,
        lines: 55
      }
    }
  }
})
