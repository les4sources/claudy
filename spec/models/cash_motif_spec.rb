require "rails_helper"

# Epic #243, phase 1 — le motif de caisse porte l'affectation.
RSpec.describe CashMotif do
  let(:entity) { LegalEntity.create!(name: "Fondation test", form: "foundation", vat_regime: "exempt") }
  let(:account) { GeneralAccount.create!(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue") }

  def build_motif(**attrs)
    described_class.new({ label: "Bar", direction: "in",
                          general_account: account, legal_entity: entity }.merge(attrs))
  end

  it "exige un compte général — un motif qui n'affecte rien n'a pas de sens" do
    motif = build_motif(general_account: nil)

    expect(motif).not_to be_valid
    expect(motif.errors[:general_account]).to be_present
  end

  it "exige une entité" do
    expect(build_motif(legal_entity: nil)).not_to be_valid
  end

  it "refuse un sens inconnu" do
    expect(build_motif(direction: "sideways")).not_to be_valid
  end

  it "refuse deux motifs du même libellé" do
    build_motif.save!

    expect(build_motif).not_to be_valid
  end

  describe "#signed_cents" do
    it "rend un montant positif pour une entrée, quel que soit le signe saisi" do
      expect(build_motif(direction: "in").signed_cents(-2_500)).to eq(2_500)
    end

    it "rend un montant négatif pour une sortie" do
      expect(build_motif(direction: "out").signed_cents(2_500)).to eq(-2_500)
    end

    it "laisse la saisie décider quand le motif vaut dans les deux sens" do
      expect(build_motif(direction: "both").signed_cents(-2_500)).to eq(-2_500)
    end
  end

  it "expose l'affectation à COPIER sur la ligne, pas une référence au motif" do
    team = Team.create!(name: "Bar")
    motif = build_motif(team: team).tap(&:save!)

    expect(motif.allocation_attributes).to eq(
      general_account_id: account.id, team_id: team.id, legal_entity_id: entity.id
    )
  end

  it "propose, pour un sens, les motifs de ce sens et ceux qui valent des deux" do
    entree = build_motif(label: "Bar", direction: "in").tap(&:save!)
    sortie = build_motif(label: "Dépôt en banque", direction: "out").tap(&:save!)
    mixte  = build_motif(label: "Divers", direction: "both").tap(&:save!)

    expect(described_class.for_direction("in")).to contain_exactly(entree, mixte)
    expect(described_class.for_direction("out")).to contain_exactly(sortie, mixte)
  end

  it "se trie par position puis par id" do
    troisieme = build_motif(label: "C", position: 3).tap(&:save!)
    premier   = build_motif(label: "A", position: 1).tap(&:save!)
    deuxieme  = build_motif(label: "B", position: 2).tap(&:save!)

    expect(described_class.ordered.to_a).to eq([premier, deuxieme, troisieme])
  end

  it "donne la position suivante, en tenant compte des motifs désactivés" do
    build_motif(label: "A", position: 7).tap(&:save!)

    expect(described_class.next_position).to eq(8)
  end
end
