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

// Grille camping/van par nuit (Michael 2026-07-20) : le form Séjour admin
// embarque la même grille steppers que le funnel. On enregistre le contrôleur
// stepper public — MÊME fichier que le funnel, aucune copie de code.
import StepperController from '../controllers/public/stepper_controller.js';
application.register('public--stepper', StepperController);

// Grille hébergement par nuit (Slice C) : le form Séjour admin embarque la MÊME
// grille nuits × gîtes que le funnel (`public--stay-calendar`) plus la mini-modale
// « occupé » (`public--unavail`). Sans ces deux enregistrements, la grille reste
// inerte (clics sans effet, aucun `lodging_night_ids` généré) — le glob admin ne
// couvre que `controllers/*_controller.js`, pas `controllers/public/**`.
import StayCalendarController from '../controllers/public/stay_calendar_controller.js';
import UnavailController from '../controllers/public/unavail_controller.js';
application.register('public--stay-calendar', StayCalendarController);
application.register('public--unavail', UnavailController);

// Load and register view_components controllers
registerControllers(
  application,
  import.meta.globEager('../../components/**/*_controller.js'),
);

import TurboMorph from 'turbo-morph';
TurboMorph.initialize(window.Turbo.StreamActions);
