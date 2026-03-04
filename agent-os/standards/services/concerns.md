# Service Concerns

Shared service logic lives in `app/services/concerns/` using `ActiveSupport::Concern`.

## When to use a concern

Extract to a concern when logic represents a **domain boundary** — a coherent set of responsibilities (availability checking, notifications, params) rather than arbitrary shared code.

## Existing concerns

| Concern | Purpose | Used by |
|---------|---------|--------|
| `Bookable` | Availability, reservations, notifications, booking params | Bookings::*, Public::Bookings::* |
| `SpaceBookable` | Space availability, space reservations, space booking params | SpaceBookings::* |
| `Subscribable` | Newsletter subscription after booking | Bookings::Create, SpaceBookings::Create |
| `Routing` | URL helpers access in services | Payments::PayService |

## Structure

```ruby
module ConcernName
  extend ActiveSupport::Concern

  private

  def shared_method
    # ...
  end
end
```

All concern methods are `private`. Include via `include ConcernName` in the service class.
