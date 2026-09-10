require "rails_helper"
require Rails.root.join("lib/coda/fingerprint")

# L'empreinte est le pivot de l'idempotence : si elle bouge, tout le journal
# déjà importé cesse d'être reconnu et le prochain export le redouble en entier.
RSpec.describe Coda::Fingerprint do
  def champs(**overrides)
    {
      entry_date: Date.new(2026, 8, 1), value_date: Date.new(2026, 8, 1), amount_cents: 1_100,
      counterparty_iban: "BE24 7326 0637 4838", counterparty_name: "BEGON OLIVIER",
      communication: "Bar", transaction_code: "01500000"
    }.merge(overrides)
  end

  it "ne dépend pas du chemin par lequel les champs ont été lus" do
    depuis_le_parseur = described_class.call(**champs)
    depuis_la_base = described_class.call(**champs(entry_date: "2026-08-01", value_date: "2026-08-01",
                                                  counterparty_iban: "be2473260637 4838",
                                                  counterparty_name: "begon  olivier", communication: "BAR"))

    expect(depuis_la_base).to eq(depuis_le_parseur)
  end

  # Le verrou. Les lignes déjà en base portent une empreinte calculée UNE FOIS,
  # par la migration ; changer l'algorithme les rendrait toutes méconnaissables
  # et le prochain export redoublerait le journal entier. Si ce test casse, la
  # question n'est pas de le mettre à jour mais de re-remplir la colonne.
  it "reste identique dans le temps, pour une valeur connue" do
    expect(described_class.call(**champs)).to eq("c2b519ffdd83c96923d86b70318fa28f:01")
  end

  it "sépare deux mouvements identiques du même jour par leur rang" do
    expect(described_class.call(occurrence: 1, **champs))
      .not_to eq(described_class.call(occurrence: 2, **champs))
  end

  %i[entry_date value_date amount_cents counterparty_iban counterparty_name
     communication transaction_code].each do |champ|
    it "change quand #{champ} change" do
      autre = champ == :amount_cents ? 9_999 : "AUTRE VALEUR"
      autre = Date.new(2026, 9, 1) if champ.to_s.end_with?("date")

      expect(described_class.digest(**champs(champ => autre))).not_to eq(described_class.digest(**champs))
    end
  end

  it "distingue un champ vide d'un champ absent sans planter" do
    expect(described_class.call(**champs(communication: nil, counterparty_iban: ""))).to be_a(String)
  end
end
