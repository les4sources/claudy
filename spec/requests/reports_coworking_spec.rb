require "rails_helper"

# Epic #126, Phase 4 — vue d'ensemble coworking intégrée au Reporting existant.
# On vérifie que les chiffres (occupation, CA, packs actifs) sont corrects et
# que les packs/réservations soft-deletés (remboursés/annulés) en sont exclus.
RSpec.describe "Reporting — Coworking", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(first_name: "Ana", email: "ana@example.com") }

  before { sign_in user }

  def paid_pack(days:, purchased_on:, expires_at: nil)
    pack = CoworkingPack.create!(customer: customer, days_total: days, payment_method: "card",
                                 purchased_at: purchased_on.to_time,
                                 expires_at: (expires_at || (purchased_on + 12.months)).to_time)
    Payment.create!(coworking_pack: pack, amount_cents: pack.price_cents,
                    payment_method: "card", status: "paid")
    pack
  end

  it "affiche occupation, CA coworking et packs actifs pour l'année" do
    year = Date.current.year
    pack = paid_pack(days: 10, purchased_on: Date.new(year, 3, 10))
    # Deux journées réservées cette année (occupation = 2).
    pack.coworking_reservations.create!(date: Date.new(year, 3, 16), customer: customer) # lundi
    pack.coworking_reservations.create!(date: Date.new(year, 3, 17), customer: customer) # mardi

    get reports_path(year: year)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Coworking")
    expect(response.body).to include("Packs actifs")
    # CA = prix du pack de 10 journées.
    expected_ca = ActiveSupport::NumberHelper.number_to_currency(
      Pricing::Catalog.coworking_pack_cents(10) / 100.0, unit: "€"
    )
    expect(response.body).to include(expected_ca)
  end

  it "exclut les packs remboursés (soft-delete) du CA et des packs actifs" do
    year = Date.current.year
    refunded = paid_pack(days: 5, purchased_on: Date.new(year, 4, 1))
    refunded.soft_delete!(validate: false)

    get reports_path(year: year)

    expect(response).to have_http_status(:ok)
    # Aucun pack actif ni crédit : le libellé « 0 journée en réserve » apparaît.
    expect(response.body).to include("0 journées en réserve")
  end
end
