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
    }),
  ],
  server: {
    hmr: {
      host: 'vite.claudy.test',
      clientPort: 443,
    },
  },
})
