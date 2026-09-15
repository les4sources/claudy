// To see this message, add the following to the `<head>` section in your
// views/layouts/application.html.erb
//
//    <%= vite_client_tag %>
//    <%= vite_javascript_tag 'application' %>
console.log('Vite ⚡️ Rails')

// If using a TypeScript entrypoint file:
//     <%= vite_typescript_tag 'application' %>
//
// If you want to use .jsx or .tsx, add the extension:
//     <%= vite_javascript_tag 'application.jsx' %>

// Example: Load Rails libraries in Vite.
//
// import * as Turbo from '@hotwired/turbo'
// Turbo.start()
//
// import ActiveStorage from '@rails/activestorage'
// ActiveStorage.start()
//
// // Import all channels.
// const channels = import.meta.globEager('./**/*_channel.js')

// Example: Import a stylesheet in app/frontend/index.css
// import '~/index.css'

import '@hotwired/turbo-rails';
// import.meta.globEager('../channels/**/*_channel.js');

import 'flowbite/dist/datepicker';
import '../utils/datepicker.turbo.min.js';

// Éditeur de texte riche d'Action Text (issue #312) : Lexxy remplace Trix partout.
// `@rails/activestorage` est la dépendance dont Lexxy se sert pour téléverser les
// pièces jointes ; `ActiveStorage.start()` est nécessaire car plus rien d'autre ne
// le démarre depuis la disparition de `@rails/actiontext`.
import '@37signals/lexxy';
import * as ActiveStorage from '@rails/activestorage';
ActiveStorage.start();

import '../utils/setupStimulus';

import '../stylesheets/application.css';
