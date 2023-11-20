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
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
        caveat: ['Caveat', 'Inter var', ...defaultTheme.fontFamily.sans]
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/typography'),
    require('flowbite/plugin')
  ],
  purge: {
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
    ],
  }
}
