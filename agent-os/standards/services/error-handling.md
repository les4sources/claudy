# Service Error Handling

`ServiceBase` provides two error mechanisms.

## catch_error — exception wrapper

Used in `run()` to wrap `run!()`. Rescues all exceptions, logs them, optionally reports to Sentry.

```ruby
def run(params = {})
  catch_error(context: { params: params }) do
    run!(params)
  end
end
```

- Sets `@error` to the caught exception
- Returns `false` on failure
- Pass `context:` hash for debugging (logged on error)
- Set `@report_errors = true` in `initialize` to report to Sentry

## set_error_message — validation-style errors

For business rule failures that aren't exceptions (e.g., "lodging not available"):

```ruby
set_error_message("Cet hébergement n'est pas disponible.")
return false
```

After `run!()` completes, check and re-raise if an error was set:

```ruby
raise error_message if !error.nil?
true
```

## Controller usage

```ruby
service = Bookings::CreateService.new
if service.run(params)
  # success — access service.booking
else
  # failure — access service.error_message
end
```

`error_message(default:)` returns the error's message or a default string.
