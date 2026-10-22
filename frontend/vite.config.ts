import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  // Relative asset paths, so the build works under /strata-taskbar/ on GitHub Pages or at a custom domain.
  base: './',
  plugins: [react(), tailwindcss()],
})
