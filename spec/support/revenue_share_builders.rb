# Helpers de construction pour les specs de partage de revenus (issue #247).
#
# Même parti pris que `FinanceBuilders` : pas de FactoryBot, mais un décor
# nommable. Un relevé de partage demande un hébergement, un accord et des
# réservations avec un prix persisté — répété tel quel dans cinq fichiers, le
# setup finirait par cacher ce que la spec teste.
module RevenueShareBuilders
  def build_tiny_house(name: "Tiny house")
    Lodging.create!(name: name, price_night_cents: 9_000)
  end

  def build_agreement(lodging, **attrs)
    RevenueShareAgreement.create!({
      lodging: lodging,
      beneficiary_name: "Famille Dubois",
      beneficiary_email: "dubois@example.com",
      beneficiary_iban: "BE68539007547034",
      share_percent: 50,
      period: "quarterly",
      starts_on: Date.new(2026, 1, 1)
    }.merge(attrs))
  end

  def build_tiny_booking(lodging, from:, to: nil, price_cents: 50_000, status: "confirmed", **attrs)
    Booking.create!({
      lodging: lodging,
      firstname: "Client",
      email: "client-#{SecureRandom.hex(4)}@example.com",
      from_date: from,
      to_date: to || (from + 2.days),
      adults: 2,
      status: status,
      price_cents: price_cents
    }.merge(attrs))
  end
end
