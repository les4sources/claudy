import { Application } from '@hotwired/stimulus';
import { registerControllers } from 'stimulus-vite-helpers';
import { Alert, Autosave, Dropdown, Modal, Tabs, Popover, Toggle, Slideover } from 'tailwindcss-stimulus-components';

// Start Stimulus application
const application = Application.start();

// Configure Stimulus development experience
application.warnings = true;
application.debug = false;
window.Stimulus = application;

// Import and register all TailwindCSS Components
application.register('alert', Alert)
// application.register('autosave', Autosave)
application.register('dropdown', Dropdown)
application.register('modal', Modal)
application.register('tabs', Tabs)
application.register('popover', Popover)
application.register('toggle', Toggle)
application.register('slideover', Slideover)

// Load and register global controllers
registerControllers(
  application,
  import.meta.globEager('../controllers/public/*_controller.js'),
);

// Load and register view_components controllers
registerControllers(
  application,
  import.meta.globEager('../../components/**/*_controller.js'),
);

import TurboMorph from 'turbo-morph';
TurboMorph.initialize(window.Turbo.StreamActions);
