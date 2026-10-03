import { Controller } from '@hotwired/stimulus';
import { enter, leave } from 'el-transition';

export default class extends Controller {
  static targets = ['dialog', 'inner'];

  connect() {
    this.element.dataset.action =
      'turbo:submit-end->turbo-modal--component#submitEnd \
       turbo:before-render@document->turbo-modal--component#closeBeforeRender \
       keyup@window->turbo-modal--component#closeWithKeyboard \
       click@window->turbo-modal--component#closeBackground \
       keydown@window->turbo-modal--component#trapFocus';

    // Le focus entre dans la modale à l'ouverture, et revient à la fermeture
    // sur l'élément qui l'a ouverte (epic #288, phase 5) : au clavier, on
    // reprend là où on en était.
    const active = document.activeElement;
    this.opener = active && active !== document.body ? active : null;
    this.dialogTarget.focus({ preventScroll: true });

    enter(this.dialogTarget);
  }

  // Tab et Maj+Tab tournent DANS la modale tant qu'elle est ouverte.
  trapFocus(event) {
    if (event.key !== 'Tab') return;

    const focusables = Array.from(
      this.dialogTarget.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => el.offsetParent !== null);
    if (focusables.length === 0) {
      event.preventDefault();
      return;
    }

    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    const inside = this.dialogTarget.contains(document.activeElement);

    if (event.shiftKey && (document.activeElement === first || !inside || document.activeElement === this.dialogTarget)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (document.activeElement === last || !inside)) {
      event.preventDefault();
      first.focus();
    }
  }

  // Close dialog with animation
  closeDialog(event) {
    // Remove src reference from parent frame element (just to clean up)
    this.element.parentElement.removeAttribute('src');

    leave(this.dialogTarget).then(() => {
      this.dialogTarget.remove();
      if (this.opener?.isConnected) this.opener.focus({ preventScroll: true });

      if (event?.detail.resume) event.detail.resume();
    });
  }

  // Ensure to close dialog (with animation) BEFORE Turbo renders new page
  closeBeforeRender(event) {
    event.preventDefault();
    this.closeDialog(event);
  }

  // Close dialog on successful form submission
  submitEnd(event) {
    // add data-keep-turbo-frame-open="true" to avoid frame being closed on Turbo Stream event 
    // happening inside the frame
    if (event.srcElement.getElementsByTagName('button')[0].dataset['keepTurboFrameOpen'] != 'true') {
      if (event.detail.success) this.closeDialog();
    }
  }

  // Close dialog when clicking ESC
  closeWithKeyboard(event) {
    if (event.code == 'Escape') this.closeDialog();
  }

  // Close dialog when clicking outside
  closeBackground(event) {
    if (event && this.innerTarget.contains(event.target)) return;

    this.closeDialog();
  }
}
