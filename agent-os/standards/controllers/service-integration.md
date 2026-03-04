# Service Integration in Controllers

Controllers delegate all business logic to service objects.

## Create pattern

```ruby
def create
  service = Bookings::CreateService.new
  if service.run(params)
    redirect_to booking_url(service.booking), notice: "Réservation créée."
  else
    set_error_flash(service)
    @booking = service.booking
    render :new, status: :unprocessable_entity
  end
end
```

## Update pattern

```ruby
def update
  service = Bookings::UpdateService.new(booking_id: params[:id])
  if service.run(params)
    redirect_to booking_url(service.booking)
  else
    set_error_flash(service)
    @booking = service.booking.decorate
    render :edit, status: :unprocessable_entity
  end
end
```

## Key points

- Initialize service with IDs (for update/destroy), not full objects
- Call `service.run(params)` — returns true/false
- Access results via `service.booking`, `service.payment`, etc.
- On failure: `set_error_flash(service)` to show `service.error_message`
- Decorate the result for re-rendering: `service.booking.decorate`
