# Service Structure

All services inherit from `ServiceBase`.

## Dual-method pattern

Services expose `run(params)` and `run!(params)`:

- `run!()` — Contains the business logic. Raises on failure.
- `run()` — Wraps `run!()` with `catch_error`. Returns `false` on failure, sets `@error`.

```ruby
def run(params = {})
  catch_error(context: { params: params }) do
    run!(params)
  end
end

def run!(params = {})
  # business logic here
  true
end
```

Controllers call `run()`. Internal service-to-service calls may use `run!()` directly.

Simple services that are only called internally can implement `run!()` alone (skip `run()`).

## Return values

- `run!()` returns `true` on success, `false` for validation failures, raises for errors
- `run()` returns `true` on success, `false` on any failure (errors captured in `@error`)

## Instance variables

Expose the primary record via `attr_reader` (e.g., `attr_reader :booking`). Callers access results through this after calling `run`.
