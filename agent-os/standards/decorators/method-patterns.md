# Decorator Method Patterns

Common method types found across decorators.

## Status badges

Colored `<span>` tags using Tailwind classes. Pattern: `shared_classes` + status-specific color.

```ruby
def status
  shared_classes = "text-xs font-medium mr-2 px-2.5 py-0.5 rounded"
  case object.status
  when "confirmed"
    h.content_tag(:span, "Confirmée", class: "#{shared_classes} bg-green-100 text-green-800")
  when "pending"
    h.content_tag(:span, "En attente", class: "#{shared_classes} bg-yellow-100 text-yellow-800")
  end
end
```

## Emoji helpers

For compact display contexts (calendars, summaries):

```ruby
def status_emoji
  case object.status
  when "confirmed" then h.content_tag(:span, "✅")
  when "pending" then h.content_tag(:span, "⏳")
  end
end
```

## Formatting

- Currency: `h.number_to_currency(amount)` or `h.humanized_money_with_symbol(object.price)`
- Dates: `l(object.from_date, format: :short)` (uses Rails I18n)
- Booleans: `object.field? ? "OUI" : "non"`

## CSS class methods

Methods returning Tailwind class strings for use in views:

```ruby
def tr_class
  object.confirmed? ? "bg-white" : "bg-yellow-50 opacity-75"
end
```

## French localization

All user-facing text is in French. Status labels, error messages, and display values use French.
