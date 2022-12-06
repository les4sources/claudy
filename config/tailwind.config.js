const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/**/*.{html.erb,html.slim,rb}',
    './app/javascript/**/*.js'
    // './app/helpers/**/*.rb',
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
  ]
}
