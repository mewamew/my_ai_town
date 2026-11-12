import { defineConfig } from 'vite'
import { writeClientBuildState } from '../../scripts/client-build-state.mjs'
import { fileURLToPath } from 'node:url'
const proxy = {
  '/data/props': { target: `http://127.0.0.1:${process.env.TOWN_MANAGER_PORT ?? 8788}` },
  '/api/towns': { target: `http://127.0.0.1:${process.env.TOWN_MANAGER_PORT ?? 8788}` },
}
export default defineConfig({
  publicDir: false,
  plugins: [
    {
      name: 'formal-client-build-state',
      apply: 'build',
      async closeBundle() {
        await writeClientBuildState(
          fileURLToPath(new URL('../../', import.meta.url)),
          fileURLToPath(new URL('./dist', import.meta.url))
        )
      },
    },
  ],
  server: { port: 5174, host: '127.0.0.1', strictPort: true, proxy },
  preview: { port: 5174, host: '127.0.0.1', strictPort: true, proxy },
  build: {
    rollupOptions: {
      input: { index: 'index.html', game: 'game.html' },
    },
  },
})
