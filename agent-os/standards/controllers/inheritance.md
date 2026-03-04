# Controller Inheritance

Two base controllers, both inheriting from `ActionController::Base`:

## BaseController (admin)

```ruby
class BaseController < ActionController::Base
  include PublicActivity::StoreController
  layout "application"
  before_action :authenticate_user!  # Devise
  before_action :set_paper_trail_whodunnit
end
```

- All admin controllers inherit from `BaseController`
- Overrides `render` to call `set_presenters` (sets `@menu_presenter`)
- Provides `set_error_flash(service)` helper

## Public::BaseController (public-facing)

```ruby
class Public::BaseController < ActionController::Base
  layout "public"
end
```

- No authentication
- Used for public booking flow, public calendars
- Same `set_error_flash` pattern

## Layout assignments

| Controller | Layout |
|-----------|--------|
| BaseController (default) | `application` |
| PaymentsController | `modal` (except index/show → `application`) |
| Public::BaseController | `public` |
| Public::BookingsController | `public_sheet` |

## Note

`ApplicationController` exists but is empty — can be cleaned up.
