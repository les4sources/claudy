require "rails_helper"

# Epic #234, Phase 3 — le résumé en clair et l'indication de tarif. Ces deux
# textes sont rendus ici au chargement puis recalculés à l'identique par
# `spaces_calendar_controller.js` : les cas limites se fixent donc ici.
RSpec.describe SpacesGridHelper, type: :helper do
  let(:lundi)    { Date.new(2026, 6, 8) }
  let(:jours)    { (lundi..(lundi + 4)).to_a } # lundi 8 → vendredi 12

  describe "#spaces_summary_line" do
    it "rend nil quand la ligne est vide" do
      expect(helper.spaces_summary_line(["", "", "", "", ""], jours)).to be_nil
      expect(helper.spaces_summary_line(nil, jours)).to be_nil
    end

    it "compte les journées et borne la plage" do
      periodes = %w[journee journee journee journee journee]

      expect(helper.spaces_summary_line(periodes, jours)).to eq("5 journées · lun 8 → ven 12")
    end

    it "ajoute les soirées, « journée et soirée » comptant dans les deux" do
      periodes = ["journee", "", "journee_et_soiree", "", "soiree"]

      expect(helper.spaces_summary_line(periodes, jours)).to eq("2 journées · + 2 soirées · lun 8 → ven 12")
    end

    it "n'affiche pas de plage pour un seul jour" do
      periodes = ["", "", "journee", "", ""]

      expect(helper.spaces_summary_line(periodes, jours)).to eq("1 journée · mer 10")
    end

    it "sait ne dire que des soirées" do
      periodes = ["soiree", "soiree", "", "", ""]

      expect(helper.spaces_summary_line(periodes, jours)).to eq("+ 2 soirées · lun 8 → mar 9")
    end
  end

  describe "#space_rate_hint" do
    it "dérive journée, soirée et forfait 5 jours du catalogue" do
      expect(helper.space_rate_hint("petite_salle")).to eq("140 €/j · 90 €/soir · 525 € les 5 jours")
      expect(helper.space_rate_hint("grande_salle")).to eq("290 €/j · 190 €/soir · 990 € les 5 jours")
    end

    it "suit la table `rates` avant les constantes" do
      Rate.create!(key: "hall.cuisine_pro.cinq_jours", amount_cents: 35_000, label: "Cuisine pro — 5 jours")
      Pricing::Rates.reset!

      expect(helper.space_rate_hint("cuisine_pro")).to include("350 € les 5 jours")
    ensure
      Pricing::Rates.reset!
    end
  end
end
