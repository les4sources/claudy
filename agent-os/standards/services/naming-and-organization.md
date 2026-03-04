# Service Naming & Organization

## File structure

```
app/services/
  service_base.rb
  concerns/
    bookable.rb
  bookings/
    create_service.rb
    update_service.rb
    duplicate_service.rb
  payments/
    create_service.rb
    pay_service.rb
  public/
    bookings/
      create_service.rb
```

## Naming convention

`Module::ActionService` — e.g., `Bookings::CreateService`, `Payments::PayService`

- Use CRUD names when they fit: `CreateService`, `UpdateService`, `DestroyService`
- Use domain-specific names when CRUD doesn't fit: `PayService`, `DuplicateService`
- Module name is the pluralized domain: `Bookings`, `Payments`, `Events`

## Namespace mirroring

Public-facing services mirror the controller namespace: `Public::Bookings::CreateService` for public booking creation.

## One action per service

Each service handles one action. Don't combine create + update logic in a single service.
