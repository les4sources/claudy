# Decorator Structure

Uses [Draper](https://github.com/drapergem/draper) for presentation logic. Decorators wrap models with view-specific methods.

## Base class

```ruby
class ApplicationDecorator < Draper::Decorator
end
```

## Standard decorator

```ruby
class BookingDecorator < ApplicationDecorator
  delegate_all
  decorates_association :payments  # optional: decorate related models

  def self.collection_decorator_class
    PaginatingDecorator  # for paginated collections
  end

  def status
    # presentation logic here
  end
end
```

## Key conventions

- `delegate_all` — always include so `object` methods pass through
- `decorates_association` — use when you need decorated versions of associations
- Access the raw model via `object` (e.g., `object.status`)
- Access view helpers via `h` (e.g., `h.content_tag`, `h.number_to_currency`)
- Only create a decorator when the model needs presentation logic

## Collections

`PaginatingDecorator` extends `Draper::CollectionDecorator` and delegates pagination methods (`current_page`, `total_pages`, etc.).
