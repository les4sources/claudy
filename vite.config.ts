import { defineConfig } from 'vite'
import ViteRails from 'vite-plugin-rails'

export default defineConfig({
  plugins: [
    ViteRails({
      fullReload: {
        additionalPaths: [
          'config/routes.rb',
          'app/views/**/*',
          'app/components/**/*',
          'config/locales/**/*.yml',
        ],
      },
    })
  ],
  server: {
    port: 3000,
    hmr: {
      // host: 'vite.claudy.test',
      host: 'mhulet-symmetrical-tribble-vq796p7g5hp6r5-3036.preview.app.github.dev',
      clientPort: 80
    },
  },
})
