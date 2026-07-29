const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/**/*.{html.erb,html.slim,rb,js}',
    './app/calendars/**/*.{html.erb,html.slim,rb,js}',
    './app/components/**/*.{html.erb,html.slim,rb,js}',
    './app/decorators/**/*.{html.erb,html.slim,rb,js}',
    './app/frontend/**/*.{html.erb,html.slim,rb,js}',
    './app/lib/form_builders/**/*.rb',
    './app/inputs/**/*.{html.erb,html.slim,rb,js}',
    './app/presenters/**/*.{html.erb,html.slim,rb,js}',
    './app/views/**/*.{html.erb,html.slim,rb,js}',
    './node_modules/flowbite/**/*.js',
    // './app/javascript/**/*.js',
    // './app/simple_form/builders/**/*.rb',
    // './app/views/**/*.{erb,haml,html,slim}',
    // './app/views/**/*.html.slim'
  ],
  theme: {
    extend: {
      colors: {
        '4s-main': '#024442',
        // Charte « sous-bois » — mêmes valeurs que les tokens --p-* de
        // portal.css, exposées comme couleurs Tailwind pour que le funnel
        // public (/reservation) parle la langue de la marque au lieu de
        // l'emerald générique. Une seule source de vérité : si une valeur
        // bouge ici, la bouger aussi dans portal.css:36 (et inversement).
        sand:   { DEFAULT: '#F7F2E9', deep: '#EFE7D6' },
        forest: { DEFAULT: '#0B3D3A', soft: '#12524D', tint: '#E4EEEA' },
        ember:  { DEFAULT: '#C97B3D', tint: '#F5E3D0' },
        bark:   { DEFAULT: '#E4DBC8', deep: '#DED4BE' },
        ink:    '#1C2620',
        // Un cran plus sombre que le `--p-muted` du portail (#6B7568) : sur le
        // fond sable, celui-ci plafonne à 4.31:1, sous le seuil AA de 4.5 pour
        // du texte courant — et le funnel s'en sert pour TOUTES ses mentions
        // secondaires (prix à la nuit, règles, contacts). #5C6659 donne 5.38:1
        // sur sable, 6.00:1 sur blanc, 4.88:1 sur sable profond.
        moss:   '#5C6659'
      },
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
        caveat: ['Caveat', 'Inter var', ...defaultTheme.fontFamily.sans],
        // Titres de page — auto-hébergée (cf. @font-face dans application.css).
        averia: ['Averia Serif Libre', ...defaultTheme.fontFamily.serif],
        // Titres du funnel public + portail — Fraunces variable auto-hébergée
        // (cf. @font-face dans portal.css, chargée par public.css).
        fraunces: ['Fraunces', 'Georgia', 'Iowan Old Style', ...defaultTheme.fontFamily.serif]
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/typography'),
    require('flowbite/plugin')
  ],
  safelist: [
    'bg-slate-300',
    'bg-gray-300',
    'bg-zinc-300',
    'bg-neutral-300',
    'bg-stone-300',
    'bg-red-300',
    'bg-orange-300',
    'bg-amber-300',
    'bg-yellow-300',
    'bg-lime-300',
    'bg-emerald-300',
    'bg-teal-300',
    'bg-cyan-300',
    'bg-sky-300',
    'bg-green-300',
    'bg-blue-300',
    'bg-indigo-300',
    'bg-violet-300',
    'bg-purple-300',
    'bg-fuchsia-300',
    'bg-pink-300',
    'bg-rose-300',
    'text-yellow-900',
    'text-pink-900',
    'text-blue-900',
    'text-green-900',
    'bg-yellow-500',
    'bg-pink-500',
    'bg-blue-500',
    'bg-green-500',
    'bg-orange-500',
    'border-red-200',
    'border-gray-200',
    'border-yellow-200',
    'border-green-200',
    'border-yellow-500',
    'border-pink-500',
    'border-blue-500',
    'border-yellow-500',
    // Dynamic category colors (GatheringCategory/EventCategory) — full Tailwind palette
    // so any color name stored in DB renders without re-seeding the safelist.
    { pattern: /^(bg|border|text|ring)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-(50|100|200|300|400|500|600|700|800|900)$/ },
    { pattern: /^border-l-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-(400|500|600)$/ }
  ],
}
