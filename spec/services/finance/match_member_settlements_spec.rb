require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #349 — les propositions de règlement sur « À affecter ».
RSpec.describe Finance::MatchMemberSettlements do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4) }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }

  let!(:bene) { Human.create!(name: "Bénédicte Lambert") }
  let!(:compte_bene) { MemberAccount.for_human!(bene) }

  let!(:menage) { Household.create!(name: "Ménage Dupuis", kind: "resident") }
  let!(:compte_menage) { MemberAccount.create!(kind: "household", household: menage, name: "Ménage Dupuis") }

  # Deux dettes distinctes : 75 € pour Béné, 350 € pour le ménage.
  before do
    compte_bene.account_entries.create!(entry_date: Date.new(2026, 9, 1), kind: "recurring", flow: "charges",
                                        label: "Frais mensuels", amount_cents: 7_500)
    compte_menage.account_entries.create!(entry_date: Date.new(2026, 9, 1), kind: "recurring", flow: "charges",
                                          label: "Loyer", amount_cents: 35_000)
  end

  def entrante(cents, communication: nil, iban: nil, nom: nil, date: Date.new(2026, 9, 5))
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: date, label: "Virement reçu")
    entry.update!(communication: communication, counterparty_iban: iban, counterparty_name: nom)
    entry
  end

  describe "les indices" do
    it "reconnaît le code du compte dans la communication" do
      matches = described_class.new.for_entry(entrante(1_000, communication: "Paiement #{compte_bene.code} merci"))

      expect(matches.first.member_account).to eq(compte_bene)
      expect(matches.first.confidence).to eq(95)
      expect(matches.first.reason).to include(compte_bene.code)
    end

    # La communication arrive avec la ponctuation de l'habitant, jamais celle
    # qu'on lui a donnée.
    it "reconnaît le code malgré les espaces et la casse" do
      code_espace = compte_bene.code.downcase.insert(4, " ")
      matches = described_class.new.for_entry(entrante(1_000, communication: "virement #{code_espace} merci"))

      expect(matches.first.member_account).to eq(compte_bene)
    end

    it "reconnaît un IBAN déjà rapproché sur ce compte" do
      deja_vu = build_cash_entry(compte_bancaire, amount_cents: 1_000, label: "Ancien virement")
      deja_vu.update!(counterparty_iban: "BE68 5390 0754 7034")
      deja_vu.cash_allocations.create!(general_account: clients, legal_entity: entity,
                                       document: compte_bene, amount_cents: 1_000)

      matches = described_class.new.for_entry(entrante(1_000, iban: "BE68539007547034"))

      expect(matches.first.member_account).to eq(compte_bene)
      expect(matches.first.confidence).to eq(85)
    end

    it "reconnaît le nom de la contrepartie" do
      matches = described_class.new.for_entry(entrante(1_000, nom: "LAMBERT BENEDICTE"))

      expect(matches.first.member_account).to eq(compte_bene)
      expect(matches.first.confidence).to eq(70)
    end

    # Un virement d'un ménage part du compte d'une seule des personnes qui y
    # vivent : c'est son nom qui arrive sur la ligne, pas celui du ménage.
    it "reconnaît le nom d'un membre du ménage" do
      menage.household_members.create!(name: "Sophie Vandenberghe", kind: "adult",
                                       started_on: Date.new(2020, 1, 1))

      matches = described_class.new.for_entry(entrante(1_000, nom: "VANDENBERGHE SOPHIE"))

      expect(matches.first.member_account).to eq(compte_menage)
      expect(matches.first.reason).to include("Sophie Vandenberghe")
    end

    it "reconnaît le montant exactement dû" do
      matches = described_class.new.for_entry(entrante(35_000))

      expect(matches.first.member_account).to eq(compte_menage)
      expect(matches.first.confidence).to eq(60)
      expect(matches.first.due_cents).to eq(35_000)
    end

    # Un mot de deux lettres n'est pas un indice : « de » rapprocherait la
    # moitié du village.
    it "ne rapproche pas sur une particule" do
      compte_menage.update!(name: "Ménage de la Forge")

      expect(described_class.new.for_entry(entrante(1_000, nom: "DE SMET Julien"))).to be_empty
    end
  end

  describe "l'ordre et le périmètre" do
    it "classe les propositions par confiance décroissante" do
      entry = entrante(35_000, communication: compte_bene.code)

      matches = described_class.new.for_entry(entry)

      expect(matches.map(&:confidence)).to eq(matches.map(&:confidence).sort.reverse)
      expect(matches.first.member_account).to eq(compte_bene)
    end

    # Un compte ne doit apparaître qu'une fois : deux propositions du même compte
    # à deux confiances n'aident personne à décider.
    it "ne propose un compte qu'une fois" do
      entry = entrante(7_500, communication: compte_bene.code, nom: "LAMBERT")

      matches = described_class.new.for_entry(entry)

      expect(matches.count { |m| m.member_account == compte_bene }).to eq(1)
    end

    it "ne propose jamais un compte créditeur" do
      compte_bene.account_entries.create!(entry_date: Date.new(2026, 9, 2), kind: "settlement", flow: "other",
                                          label: "Trop-perçu", amount_cents: -10_000)

      expect(described_class.new.for_entry(entrante(1_000, nom: "LAMBERT")).map(&:member_account))
        .not_to include(compte_bene)
    end

    it "ne propose jamais un compte à zéro" do
      compte_bene.account_entries.destroy_all

      expect(described_class.new.for_entry(entrante(1_000, nom: "LAMBERT")).map(&:member_account))
        .not_to include(compte_bene)
    end

    it "ne propose rien sur une ligne sortante" do
      entry = build_cash_entry(compte_bancaire, amount_cents: -35_000, label: "Virement émis")

      expect(described_class.new.for_entry(entry)).to be_empty
    end

    it "ne propose rien sur une ligne déjà affectée" do
      entry = entrante(35_000)
      entry.cash_allocations.create!(general_account: clients, legal_entity: entity, amount_cents: 35_000)

      expect(described_class.new.for_entry(entry.reload)).to be_empty
    end
  end

  describe "#for_entries" do
    it "rend un hash indexé par ligne, sans les lignes sans proposition" do
      avec = entrante(35_000)
      sans = entrante(12_345)

      resultat = described_class.new.for_entries([avec, sans])

      expect(resultat.keys).to eq([avec.id])
      expect(resultat[avec.id].first.member_account).to eq(compte_menage)
    end

    # C'est le rapprochement ligne à ligne qui avait fait tomber cet écran à
    # l'issue #202. Ce qui compte n'est pas un nombre de requêtes absolu — les
    # soldes et le poste présélectionné en demandent chacun une — mais qu'il ne
    # GRANDISSE PAS avec le nombre de lignes affichées.
    def requetes_pour(nombre)
      entries = Array.new(nombre) { |i| entrante(35_000, date: Date.new(2026, 9, 5) + i) }
      compte = 0
      souscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        compte += 1 if payload[:sql].to_s.include?("account_entries")
      end
      described_class.new.for_entries(entries)
      ActiveSupport::Notifications.unsubscribe(souscription)
      compte
    end

    it "ne recalcule pas les soldes ligne par ligne" do
      expect(requetes_pour(20)).to eq(requetes_pour(5))
      expect(requetes_pour(5)).to be <= 2
    end
  end
  # Le poste présélectionné : lu dans la communication quand elle le dit, sinon
  # celui qui doit le plus. Ce n'est qu'une présélection — c'est l'humain qui
  # tranche depuis l'écran.
  describe "le poste présélectionné" do
    def poste_propose(ligne, compte)
      described_class.new.for_entry(ligne).find { |m| m.member_account == compte }&.flow
    end

    it "se lit dans la communication quand elle le nomme" do
      ligne = entrante(35_000, communication: "Bar avril 2026")

      expect(poste_propose(ligne, compte_menage)).to eq("bar")
    end

    it "reconnaît les charges, le loyer et la participation" do
      ligne = entrante(35_000, communication: "Participation famille Vanhamme")

      expect(poste_propose(ligne, compte_menage)).to eq("charges")
    end

    # Le ménage doit 350 € de charges et 500 € de bar : sans indice dans la
    # communication, c'est le bar qu'on propose d'éteindre.
    it "retombe sur le poste qui doit le plus quand la communication ne dit rien" do
      compte_menage.account_entries.create!(entry_date: Date.new(2026, 8, 31), flow: "bar",
                                            label: "Bar d'août", amount_cents: 50_000)
      ligne = entrante(85_000, communication: "virement")

      expect(poste_propose(ligne, compte_menage)).to eq("bar")
    end
  end

end
