# Response Formats

Controllers respond to HTML and Turbo Stream. JSON format exists in some controllers but is a scaffolding leftover.

## Standard response pattern

```ruby
respond_to do |format|
  if service.run(params)
    format.turbo_stream { @payment = PaymentDecorator.decorate(service.payment) }
    format.html { redirect_to booking_url(service.booking), notice: "..." }
  else
    format.html { render :new, status: :unprocessable_entity }
  end
end
```

## Turbo Stream

- Used for inline updates (modals, lists) without full page reload
- Turbo Stream templates live alongside regular views (e.g., `create.turbo_stream.slim`)
- `ensure_frame_response` before_action validates Turbo Frame requests in development

## Turbo Frames

- `render layout: !turbo_frame_request?` — skip layout when rendering inside a frame
- `render layout: false` for frame-only responses

## HTML

- Success: `redirect_to` with `notice:`
- Failure: `render :action, status: :unprocessable_entity`
