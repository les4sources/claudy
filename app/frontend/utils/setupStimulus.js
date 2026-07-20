import { Application } from '@hotwired/stimulus';
import { registerControllers } from 'stimulus-vite-helpers';
import { Alert, Autosave, Modal, Tabs, Toggle, Slideover } from 'tailwindcss-stimulus-components';

// Start Stimulus application
const application = Application.start();

// Configure Stimulus development experience
application.warnings = true;
application.debug = false;
window.Stimulus = application;

// Import and register all TailwindCSS Components
application.register('alert', Alert)
application.register('autosave', Autosave)
application.register('modal', Modal)
application.register('tabs', Tabs)
application.register('toggle', Toggle)
application.register('slideover', Slideover)

// Load and register global controllers
registerControllers(
  application,
  import.meta.globEager('../controllers/*_controller.js'),
);

// Réutilisation SANS duplication (issue parité funnel) : le form Séjour admin
// embarque la grille espaces date-par-date du funnel. On enregistre ici les DEUX
// contrôleurs publics qu'elle utilise, en important les MÊMES fichiers que le
// funnel — pas de copie de code. Les identifiants (`public--…`) correspondent aux
// `data-controller` du partial partagé.
import SpaceSlotController from '../controllers/public/space_slot_controller.js';
import SpacesCalendarController from '../controllers/public/spaces_calendar_controller.js';
application.register('public--space-slot', SpaceSlotController);
application.register('public--spaces-calendar', SpacesCalendarController);

// Load and register view_components controllers
registerControllers(
  application,
  import.meta.globEager('../../components/**/*_controller.js'),
);

import TurboMorph from 'turbo-morph';
TurboMorph.initialize(window.Turbo.StreamActions);
