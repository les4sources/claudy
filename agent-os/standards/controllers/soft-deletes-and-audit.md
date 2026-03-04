# Soft Deletes & Audit Logging

## Soft deletes

All models use soft deletes. Never use `destroy` — use `soft_delete!` instead.

```ruby
def destroy
  @booking.soft_delete!(validate: false)
  @booking.create_activity(:destroy)
  redirect_to bookings_url, notice: "Réservation supprimée."
end
```

- `soft_delete!(validate: false)` — sets `deleted_at` timestamp, skips validations
- Use `Booking.unscoped` to include soft-deleted records in queries

## Audit logging

**PaperTrail** — tracks model changes (who changed what, when):
- `set_paper_trail_whodunnit` in `BaseController` before_action
- Automatic version tracking on model updates

**PublicActivity** — records user-visible activity:
- `BaseController` includes `PublicActivity::StoreController`
- Call `create_activity(:destroy)` explicitly on soft delete
- Other CRUD activities are tracked automatically
