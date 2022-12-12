const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/**/*.{html.erb,html.slim,rb,js}',
    './app/calendars/**/*.{html.erb,html.slim,rb,js}',
    './app/components/**/*.{html.erb,html.slim,rb,js}',
    './app/decorators/**/*.{html.erb,html.slim,rb,js}',
    './app/frontend/**/*.{html.erb,html.slim,rb,js}',
    './app/inputs/**/*.{html.erb,html.slim,rb,js}',
    './app/presenters/**/*.{html.erb,html.slim,rb,js}',
    './app/views/**/*.{html.erb,html.slim,rb,js}',
    './node_modules/flowbite/**/*.js'
    // './app/javascript/**/*.js',
    // './app/simple_form/builders/**/*.rb',
    // './app/views/**/*.{erb,haml,html,slim}',
    // './app/views/**/*.html.slim'
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans]
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/typography'),
    require('flowbite/plugin')
  ]
}
