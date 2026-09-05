require "rails_helper"

# Ligne de CUISINE (epic #66 phase 3, étendue par l'epic Cuisine #219 phase 1) :
# une demande datée rattachée directement au séjour, hors calendrier, qui porte
# désormais deux états indépendants — celui du client et celui de la cuisine.
RSpec.describe MealOrder do
  let(:customer) { Customer.create!(email: "meal@example.com", first_name: "Meal", last_name: "Test") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }

  def order(**attrs)
    described_class.create!({ stay: stay, kind: "buffet_vege", people: 3 }.merge(attrs))
  end

  describe "validations" do
    it "exige un type connu et un nombre de convives positif" do
      expect(described_class.new(stay: stay, kind: nil, people: 2)).not_to be_valid
      expect(described_class.new(stay: stay, kind: "pizza", people: 2)).not_to be_valid
      expect(described_class.new(stay: stay, kind: "buffet_vege", people: 0)).not_to be_valid
    end

    it "refuse un moment, un statut ou une validation hors nomenclature" do
      expect(described_class.new(stay: stay, kind: "repas", people: 2, moment: "petit_dej")).not_to be_valid
      expect(described_class.new(stay: stay, kind: "repas", people: 2, status: "brouillon")).not_to be_valid
      expect(described_class.new(stay: stay, kind: "repas", people: 2, validation: "peut_etre")).not_to be_valid
    end

    it "exige un motif pour un refus, jamais pour le reste" do
      line = order
      expect(line.update(validation: "refused")).to be(false)
      expect(line.update(validation: "refused", refusal_reason: "Pas disponible")).to be(true)
    end

    it "tolère une date nulle (repas du funnel public, sans date)" do
      expect(order(date: nil).date).to be_nil
    end
  end

  describe "nomenclature" do
    it "dérive la famille du type" do
      expect(described_class.new(kind: "trio").family).to eq("repas")
      expect(described_class.new(kind: "buffet_viande").family).to eq("buffet")
      expect(described_class.new(kind: "apero").family).to eq("apero")
    end

    it "expose les libellés du type et du moment" do
      expect(described_class.new(kind: "trio").label).to eq("Formule trio (midi + goûter + soir)")
      expect(described_class.new(kind: "repas", moment: "gouter").moment_label).to eq("Goûter")
      expect(described_class.new(kind: "repas").moment_label).to be_nil
    end
  end

  describe "prix" do
    it "calcule le total depuis le barème et le nombre de convives" do
      expect(order(kind: "repas", people: 4).price_cents).to eq(6_000)
    end

    it "préfère le prix unitaire surchargé au barème" do
      line = order(kind: "repas", people: 4, unit_price_cents: 2_200)
      expect(line.price_cents).to eq(8_800)
    end

    it "recalcule quand les convives changent, pas quand les notes changent" do
      line = order(kind: "repas", people: 4)
      line.update!(people: 6)
      expect(line.price_cents).to eq(9_000)

      line.update!(price_cents: 5_000, notes: "sans gluten")
      expect(line.reload.price_cents).to eq(5_000)
    end
  end

  describe "remise en attente de la validation" do
    it "rouvre la question quand la prestation change" do
      line = order(kind: "repas", people: 4, date: Date.current + 20,
                   validation: "accepted", validated_at: Time.current)

      line.update!(people: 6)

      expect(line.validation).to eq("pending")
      expect(line.validated_at).to be_nil
    end

    it "ne rouvre rien sur un changement de notes, de prix ou de responsable" do
      line = order(kind: "repas", people: 4, validation: "accepted", validated_at: Time.current)

      line.update!(notes: "deux véganes", unit_price_cents: 1_800, cost_cents: 2_000)

      expect(line.validation).to eq("accepted")
      expect(line.validated_at).to be_present
    end

    it "laisse le dernier mot à une validation posée dans la même sauvegarde" do
      line = order(kind: "repas", people: 4, validation: "accepted", validated_at: Time.current)

      line.update!(people: 6, validation: "refused", refusal_reason: "Trop de monde")

      expect(line.validation).to eq("refused")
    end
  end

  describe "portées" do
    it "sépare ce qui s'affiche, ce qui facture et ce qui attend la cuisine" do
      inquiry   = order(status: "inquiry")
      requested = order(status: "requested")
      confirmed = order(status: "confirmed", validation: "accepted")
      cancelled = order(status: "cancelled")
      refused   = order(validation: "refused", refusal_reason: "Indisponible")

      expect(stay.meal_orders.active).to match_array([inquiry, requested, confirmed])
      expect(stay.meal_orders.billable).to match_array([requested, confirmed])
      expect(stay.meal_orders.pending_validation).to match_array([inquiry, requested])
      expect(cancelled).not_to be_active
      expect(requested).to be_billable
      expect(inquiry).not_to be_billable
    end
  end

  it "sort du séjour après soft-delete (default_scope)" do
    line = order
    expect(stay.meal_orders).to include(line)
    line.soft_delete!(validate: false)
    expect(stay.meal_orders.reload).to be_empty
  end
end
