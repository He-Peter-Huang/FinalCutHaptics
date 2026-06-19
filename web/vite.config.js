import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Served from GitHub Pages at /FinalCutHaptics/ ; build straight into ../docs.
export default defineConfig({
  plugins: [vue()],
  base: '/FinalCutHaptics/',
  build: {
    outDir: '../docs',
    emptyOutDir: true,
  },
})
