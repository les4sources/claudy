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
          // Les helpers et décorateurs ÉMETTENT des classes Tailwind (badges,
          // teintes de ligne, icônes de composition). Sans eux dans la liste
          // surveillée, une classe ajoutée là n'était pas re-scannée en dev :
          // le style manquait au navigateur alors que le code était juste, et
          // seul un redémarrage de `bin/vite dev` le faisait apparaître. La
          // config Tailwind, elle, les couvrait déjà (`./app/**/*.rb`) — donc
          // la production n'a jamais été affectée, uniquement le dev.
          'app/helpers/**/*',
          'app/decorators/**/*',
          'config/locales/**/*.yml',
        ],
      },
    })
  ],
  server: {
    port: 3000,
    hmr: {
      host: 'localhost',
    },
  },
})
