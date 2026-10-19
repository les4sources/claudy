require "rails_helper"

# Prix imposé (Michael, 2026-10-19) : le client du Grand-Duc lisait « 2 000 € »
# sur sa ligne d'hébergement puis « Total 1 850 € ». Les lignes montrent le prix
# demandé, jamais le prix calculé.
RSpec.describe "Public /sejour/:token — prix imposé", type: :request do
  let(:customer) { Customer.create!(email: "grand-duc@example.com", first_name: "Nath") }
  let(:lodging)  { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 66_700) }

  def money(cents)
    ApplicationController.helpers.humanized_money_with_symbol(Money.new(cents))
  end

  def add_booking(stay, price_cents:, lodging: self.lodging)
    booking = Booking.create!(firstname: "Nath", lastname: "Laurent", lodging: lodging,
                              from_date: Date.today + 10, to_date: Date.today + 13,
                              adults: 8, status: "confirmed", booking_type: "lodging",
                              price_cents: price_cents, platform: "web")
    stay.stay_items.create!(bookable: booking)
  end

  def build_stay(price_override_cents:)
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.today + 10, departure_date: Date.today + 13,
                 price_override_cents: price_override_cents)
  end

  it "affiche le prix demandé sur l'unique ligne, pas le prix calculé" do
    stay = build_stay(price_override_cents: 185_000)
    add_booking(stay, price_cents: 200_000)
    stay.recompute_aggregates!

    get "/sejour/#{stay.token}"

    items = response.body[/data-stay-items="true".*?<\/ul>/m]
    expect(items).to include(money(185_000))
    expect(items).not_to include(money(200_000))
    expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("public.stays.items.agreed_price")))
    expect(response.body).not_to include("translation missing")
  end

  it "montre une ligne « Prix convenu » quand plusieurs lignes partagent le prix imposé" do
    stay = build_stay(price_override_cents: 185_000)
    add_booking(stay, price_cents: 120_000)
    add_booking(stay, price_cents: 80_000, lodging: Lodging.create!(name: "La Hulotte", price_night_cents: 26_700))
    stay.recompute_aggregates!

    lines = stay.reload.decorate.item_lines
    expect(lines.map { |l| l[:amount] }).to eq([nil, nil, money(185_000)])

    get "/sejour/#{stay.token}"

    items = response.body[/data-stay-items="true".*?<\/ul>/m]
    expect(items).to include(ERB::Util.html_escape(I18n.t("public.stays.items.agreed_price")))
    expect(items).not_to include(money(120_000))
    expect(items).not_to include(money(80_000))
  end

  it "garde le prix calculé de chaque ligne sans prix imposé" do
    stay = build_stay(price_override_cents: nil)
    add_booking(stay, price_cents: 200_000)
    stay.recompute_aggregates!

    expect(stay.reload.decorate.item_lines.map { |l| l[:amount] }).to eq([money(200_000)])
  end
end
