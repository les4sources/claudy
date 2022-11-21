// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "public/controllers"

// Other imports...
import jquery from "jquery"
import "foundation-sites"

window.jQuery = jquery
window.$ = jquery

$(function() {
  console.log('public.js')
  $(document).foundation();
})
