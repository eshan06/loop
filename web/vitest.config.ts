import { defineConfig } from 'vitest/config'

// Kept apart from vite.config.ts: vitest bundles its own vite version.
export default defineConfig({ test: { environment: 'node', include: ['src/**/*.test.ts'] } })
