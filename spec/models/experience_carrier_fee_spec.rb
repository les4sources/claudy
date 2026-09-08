require "rails_helper"

# Epic #244, phase 1 — la rémunération du porteur : tarif effectif, montant par
# prestation, et gel à la confirmation.
RSpec.describe "Rémunération du porteur d'activité" do
  let(:carrier) { Human.create!(name: "Sébastien", email: "seb@les4sources.be") }
  let(:experience) do
    Experience.create!(name: "Initiation vannerie", human: carrier, duration_hours: 2,
                       fixed_price_cents: 0, price_cents: 2_500, min_participants: 1)
  end

  after { Pricing::Rates.reset! }

  describe "le tarif horaire effectif" do
    it "vaut 40 €/h par défaut — le tarif horaire uniforme du collectif" do
      expect(experience.effective_carrier_hourly_cents).to eq(4_000)
    end

    it "suit la clé `activity.carrier_hourly` de Paramètres > Tarifs" do
      Rate.create!(key: "activity.carrier_hourly", amount_cents: 4_500, label: "Porteur")
      Pricing::Rates.reset!

      expect(experience.effective_carrier_hourly_cents).to eq(4_500)
    end

    it "est surchargé par le tarif propre à l'activité" do
      experience.update!(carrier_hourly_rate_cents: 6_000)

      expect(experience.effective_carrier_hourly_cents).to eq(6_000)
      expect(experience).to be_carrier_rate_overridden
    end

    it "se saisit en euros et se range en cents, virgule comprise" do
      experience.carrier_hourly_rate = "55,50"

      expect(experience.carrier_hourly_rate_cents).to eq(5_550)
      expect(experience.carrier_hourly_rate).to eq(55.5)
    end

    it "revient au tarif général quand on vide la surcharge" do
      experience.update!(carrier_hourly_rate_cents: 6_000)
      experience.carrier_hourly_rate = ""

      expect(experience.carrier_hourly_rate_cents).to be_nil
      expect(experience.effective_carrier_hourly_cents).to eq(4_000)
    end
  end

  describe "le montant d'une prestation" do
    it "vaut durée × tarif — par prestation, jamais par participant" do
      expect(experience.carrier_fee_cents_on).to eq(8_000)
    end

    it "gère les demi-heures" do
      experience.update!(duration_hours: 2.5)

      expect(experience.carrier_fee_cents_on).to eq(10_000)
    end

    it "n'existe pas sans durée en heures" do
      experience.update!(duration_hours: nil)

      expect(experience.carrier_fee_cents_on).to be_nil
    end
  end

  describe "le gel à la confirmation" do
    let(:availability) do
      ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 6, 10),
                                     starts_at: "10:00")
    end
    let(:stay) do
      Stay.create!(customer: Customer.create!(first_name: "Alice", last_name: "Martin",
                                              email: "alice@example.com"),
                   status: "pending")
    end

    def booking(status)
      ExperienceBooking.create!(experience_availability: availability, stay: stay,
                                participants: 3, status: status)
    end

    it "ne fige rien tant que la réservation est en attente" do
      expect(booking("pending").carrier_fee_cents).to be_nil
    end

    it "fige le montant quand le porteur confirme" do
      reservation = booking("pending")

      reservation.confirm!

      expect(reservation.reload.carrier_fee_cents).to eq(8_000)
    end

    it "fige aussi le montant d'une réservation créée directement en confirmée" do
      expect(booking("confirmed").carrier_fee_cents).to eq(8_000)
    end

    it "ne réécrit JAMAIS un montant déjà figé, même si le tarif change" do
      reservation = booking("confirmed")
      experience.update!(carrier_hourly_rate_cents: 9_000)

      reservation.update!(participants: 4)

      expect(reservation.reload.carrier_fee_cents).to eq(8_000)
    end

    it "laisse le montant vide quand l'activité n'a pas de durée, et le signale" do
      experience.update!(duration_hours: nil)
      reservation = booking("confirmed")

      expect(reservation.carrier_fee_cents).to be_nil
      expect(reservation).to be_carrier_fee_missing
    end

    it "prend le tarif EN VIGUEUR à la date du créneau, pas celui d'aujourd'hui" do
      rate = Rate.create!(key: "activity.carrier_hourly", amount_cents: 5_000, label: "Porteur")
      rate.rate_versions.create!(amount_cents: 3_000, active_from: Date.new(2026, 1, 1),
                                 active_until: Date.new(2026, 12, 31))
      Pricing::Rates.reset!

      expect(booking("confirmed").carrier_fee_cents).to eq(6_000) # 2 h × 30 €
    end
  end
end
