require "rails_helper"

# Epic #126, Phase 1 — journées de coworking.
RSpec.describe CoworkingReservation, type: :model do
  # 2026-09-07 est un lundi.
  let(:monday)   { Date.new(2026, 9, 7) }
  let(:saturday) { Date.new(2026, 9, 12) }

  def customer(suffix)
    Customer.create!(first_name: "C#{suffix}", last_name: "Test", email: "c#{suffix}@example.com")
  end

  def pack(days: 20, owner: customer(SecureRandom.hex(4)))
    CoworkingPack.create!(customer: owner, days_total: days, payment_method: "card")
  end

  it "dénormalise le client depuis le pack" do
    p = pack
    reservation = p.coworking_reservations.create!(date: monday)
    expect(reservation.customer).to eq(p.customer)
  end

  it "refuse un samedi ou un dimanche" do
    reservation = pack.coworking_reservations.new(date: saturday)
    expect(reservation).not_to be_valid
    expect(reservation.errors[:date].join).to include("lundi à vendredi")
  end

  it "refuse au-delà de la capacité GLOBALE de 3 bureaux par jour" do
    3.times { pack.coworking_reservations.create!(date: monday) }

    fourth = pack.coworking_reservations.new(date: monday)
    expect(fourth).not_to be_valid
    expect(fourth.errors[:date].join).to include("complet")
  end

  it "libère une place quand une journée est annulée" do
    reservations = 3.times.map { pack.coworking_reservations.create!(date: monday) }
    reservations.first.soft_delete!(validate: false)

    expect(pack.coworking_reservations.new(date: monday)).to be_valid
  end

  it "refuse quand le pack n'a plus de crédit" do
    p = pack(days: 1)
    p.coworking_reservations.create!(date: monday)

    second = p.coworking_reservations.new(date: monday + 1)
    expect(second).not_to be_valid
    expect(second.errors[:coworking_pack].join).to include("plus de journée")
  end

  it "refuse une date après l'expiration du pack" do
    p = pack
    p.update!(expires_at: monday - 1.day)

    reservation = p.coworking_reservations.new(date: monday)
    expect(reservation).not_to be_valid
    expect(reservation.errors[:coworking_pack].join).to include("expiré")
  end

  it "refuse deux journées le même jour sur le même pack" do
    p = pack
    p.coworking_reservations.create!(date: monday)

    expect(p.coworking_reservations.new(date: monday)).not_to be_valid
  end

  it "compte l'occupation d'un jour tous packs confondus" do
    2.times { pack.coworking_reservations.create!(date: monday) }

    expect(CoworkingReservation.count_on(monday)).to eq(2)
    expect(CoworkingReservation.remaining_on(monday)).to eq(1)
  end
end
