# Presenters

Presenters live in `app/presenters/` and inherit from `PresenterBase`.

## PresenterBase

Includes Rails view helpers manually (`ActionView::Helpers::*`, `Rails.application.routes.url_helpers`, etc.) since presenters don't inherit from Draper.

## When to use

- **Decorators** (Draper): Wrap a single model with presentation methods
- **Presenters**: Build complex UI components (e.g., navigation menus) that may pull from multiple sources

No firm rule — this distinction evolved organically.

## Example: MenuPresenter

```ruby
class Components::MenuPresenter < PresenterBase
  def initialize(view_context:, active_primary:, ...)
    # receives context, builds menu items
  end

  def render_primary_left_menu(options = {})
    render_menu_items(@primary_left_items, 'primary', options)
  end
end
```

Presenter is instantiated in the controller/view and called to render complex structures.
