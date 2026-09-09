require "rails_helper"

# Epic #243, phase 1 — le seed des motifs de caisse.
RSpec.describe Finance::SeedCashMotifs do
  def seed_referentiel
    LegalEntity.create!(name: described_class::DEFAULT_ENTITY, form: "foundation", vat_regime: "exempt")
    %w[570000 580000 440000 610000 700000 700200 700300].each do |code|
      GeneralAccount.create!(code: code, name: "Compte #{code}",
                             klass: code[0].to_i, nature: GeneralAccount.nature_from(code))
    end
  end

  it "sème le vocabulaire réel de la feuille de caisse" do
    seed_referentiel

    result = described_class.new.run

    expect(CashMotif.count).to eq(described_class::MOTIFS.size)
    expect(CashMotif.pluck(:label)).to include("Bar", "Épicerie", "Cellier", "Dépôt en banque",
                                               "Retrait bancaire", "Facture payée en espèces")
    expect(result.missing_accounts).to be_empty
  end

  it "range les motifs dans l'ordre de la liste, du plus fréquent au plus rare" do
    seed_referentiel
    described_class.new.run

    expect(CashMotif.ordered.first.label).to eq("Bar")
    expect(CashMotif.ordered.pluck(:position)).to eq((1..described_class::MOTIFS.size).to_a)
  end

  it "donne à chaque motif son sens" do
    seed_referentiel
    described_class.new.run

    expect(CashMotif.find_by(label: "Bar").direction).to eq("in")
    expect(CashMotif.find_by(label: "Dépôt en banque").direction).to eq("out")
    expect(CashMotif.find_by(label: "Retrait bancaire").direction).to eq("in")
  end

  it "crée la caisse centrale si elle n'existe pas" do
    seed_referentiel

    result = described_class.new.run

    caisse = CashAccount.find_by(name: described_class::CASH_ACCOUNT_NAME)
    expect(result.cash_account_created).to be(true)
    expect(caisse.kind).to eq("cash")
    expect(caisse.general_account.code).to eq("570000")
  end

  # Note de Michael (2026-09-08) : la production tient sa caisse dans « Caisse du
  # domaine ». Chercher un NOM y a créé un doublon vide, que la feuille de caisse
  # aurait ensuite garni pendant que l'argent dormait dans l'autre.
  it "ne crée AUCUNE caisse quand une caisse active existe déjà" do
    seed_referentiel
    entite = LegalEntity.ordered.first
    CashAccount.create!(name: "Caisse du domaine", kind: "cash", legal_entity: entite,
                        general_account: GeneralAccount.find_by(code: "570000"))

    result = described_class.new.run

    expect(result.cash_account_created).to be(false)
    expect(CashAccount.where(kind: "cash").count).to eq(1)
    expect(CashAccount.find_by(name: described_class::CASH_ACCOUNT_NAME)).to be_nil
  end

  it "est idempotent : relancer ne crée rien et n'écrase rien" do
    seed_referentiel
    described_class.new.run
    CashMotif.find_by(label: "Bar").update!(direction: "both", position: 99)

    expect { described_class.new.run }.not_to change(CashMotif, :count)
    expect(CashMotif.find_by(label: "Bar").direction).to eq("both")
    expect(CashMotif.find_by(label: "Bar").position).to eq(99)
  end

  it "SIGNALE un compte absent du référentiel, et ne le crée jamais" do
    seed_referentiel
    GeneralAccount.find_by(code: "700300").destroy

    result = described_class.new.run

    expect(result.missing_accounts.join).to include("700300", "Bar")
    expect(CashMotif.find_by(label: "Bar")).to be_nil
    expect(GeneralAccount.find_by(code: "700300")).to be_nil
    # Les autres motifs passent quand même — un compte manquant n'arrête rien.
    expect(CashMotif.find_by(label: "Dépôt en banque")).to be_present
  end

  it "s'arrête proprement quand le référentiel n'a pas encore été semé" do
    result = described_class.new.run

    expect(CashMotif.count).to eq(0)
    expect(result.missing_accounts.join).to include("accounting:seed_reference")
  end
end
