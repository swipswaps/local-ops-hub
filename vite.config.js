import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const base = process.env.GH_PAGES ? '/local-ops-hub/' : './'

export default defineConfig({
  plugins: [react()],
  base: base,
  server: { port: 3000, host: true },
  build: { outDir: 'dist', assetsDir: 'assets', sourcemap: true }
})
