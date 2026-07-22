require "rails_helper"

# Améliorations UX funnel (feature 4 & 5) : le Draft transporte désormais
#   - `spaces_note` : précision libre du besoin d'espace (→ note interne du
#     SpaceBooking à la création, préfixe « Demande client espaces : ») ;
#   - `needs` : besoins pré-sélectionnés à l'étape 1 (cards), pilotent le
#     masquage des blocs à l'étape 2 et survivent aux allers-retours.
RSpec.describe Reservations::Draft, "spaces_note & needs" do
  describe "round-trip session (to_h → new)" do
    it "préserve spaces_note et needs" do
      draft = described_class.new(
        spaces_note: "Arrivée 17h, 60 chaises",
        needs: %w[gite camping]
      )
      rebuilt = described_class.new(draft.to_h)

      expect(rebuilt.spaces_note).to eq("Arrivée 17h, 60 chaises")
      expect(rebuilt.needs).to eq(%w[gite camping])
    end

    it "normalise needs : dédup, sans blanc, bornés aux clés connues" do
      draft = described_class.new(needs: ["gite", "gite", "", "inconnu", "salles"])
      expect(draft.needs).to eq(%w[gite salles])
    end

    it "spaces_note vide → nil" do
      expect(described_class.new(spaces_note: "").spaces_note).to be_nil
    end

    it "needs absent → tableau vide (comportement conservateur)" do
      expect(described_class.new({}).needs).to eq([])
    end
  end
end
