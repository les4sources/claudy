require "rails_helper"

# Epic #246 — les écritures d'une session de batch cooking.
#
# Le scénario de référence est celui de l'issue : deux ménages servis (3 et 2
# portions) et deux cuisiniers. Les familles doivent 15 € et 10 €, chaque
# cuisinier gagne 8,75 € — cinq portions à 3,50 € partagées en deux.
RSpec.describe Finance::RecordBatchCooking do
  let(:cheveche) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:merle) { Household.create!(name: "Merle", kind: "resident") }
  let!(:compte_cheveche) { MemberAccount.create!(kind: "household", household: cheveche, name: "Chevêche") }
  let!(:compte_merle) { MemberAccount.create!(kind: "household", household: merle, name: "Merle") }

  let(:stephanie) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be") }
  let(:jules) { Human.create!(name: "Jules") }

  let(:session) { BatchCookingSession.create!(cooked_on: Date.new(2026, 9, 12)) }

  before do
    seed_rate("meal.batchcooking.per_person", 500)
    seed_rate("meal.batchcooking.cook_volunteering", 350)
    Pricing::Rates.reset!
  end

  # Un nouveau palier ferme le précédent — deux versions d'une même clé ne
  # peuvent pas se chevaucher, c'est ce qui rend la lecture datée univoque.
  def seed_rate(key, cents, active_from: RateVersion::ORIGIN)
    rate = Rate.find_or_create_by!(key: key) { |r| r.amount_cents = cents }
    rate.rate_versions.where(active_until: nil).where(active_from: ...active_from)
        .update_all(active_until: active_from - 1)
    rate.rate_versions.create!(amount_cents: cents, active_from: active_from)
    rate
  end

  # La session de l'issue, prête à enregistrer.
  def session_de_reference
    session.servings.create!(member_account: compte_cheveche, portions: 3)
    session.servings.create!(member_account: compte_merle, portions: 2)
    session.cooks.create!(human: stephanie, portions: 2.5)
    session.cooks.create!(human: jules, portions: 2.5)
    session
  end

  def record(seance = session)
    described_class.new(session: seance).run!
  end

  describe "les charges des ménages" do
    it "facture 5 € la portion sur le compte du ménage" do
      session_de_reference
      record

      charge = compte_cheveche.account_entries.find_by(kind: "batchcooking")
      expect(charge.amount_cents).to eq(1_500)
      expect(charge.quantity).to eq(3)
      expect(charge.unit_price_cents).to eq(500)
      expect(charge.flow).to eq("meal")
      expect(charge.entry_date).to eq(Date.new(2026, 9, 12))
      expect(compte_merle.account_entries.sum(:amount_cents)).to eq(1_000)
    end

    it "porte la clé d'idempotence attendue" do
      session_de_reference
      record

      expect(compte_cheveche.account_entries.first.idempotency_key)
        .to eq("batchcooking:#{session.id}:serving:#{compte_cheveche.id}")
    end

    it "libelle la ligne pour qu'elle se lise sur un décompte" do
      session_de_reference
      record

      expect(compte_cheveche.account_entries.first.label)
        .to eq("Batch cooking du 12/09 — 3 portions")
    end

    it "refuse un ménage dont le compte est désactivé" do
      session.servings.create!(member_account: compte_cheveche, portions: 3)
      compte_cheveche.update!(active: false)

      expect { record }.to raise_error(ServiceError, /désactivé/)
      expect(AccountEntry.count).to eq(0)
    end
  end

  describe "les crédits des cuisiniers" do
    it "crédite le compte PERSONNEL du cuisinier, pas celui de son ménage" do
      session_de_reference
      record

      compte = MemberAccount.find_by(human_id: stephanie.id)
      expect(compte.kind).to eq("human")
      expect(compte.account_entries.sum(:amount_cents)).to eq(-875)
      expect(compte.balance_cents).to eq(-875)
      expect(compte_cheveche.account_entries.where(kind: "cook_fee")).to be_empty
    end

    it "ouvre le compte personnel du cuisinier s'il n'en a pas encore" do
      session_de_reference

      expect { record }.to change { MemberAccount.where(kind: "human").count }.by(2)
    end

    it "porte la clé d'idempotence attendue et une nature lisible" do
      session_de_reference
      record

      ecriture = MemberAccount.find_by(human_id: stephanie.id).account_entries.first
      expect(ecriture.idempotency_key).to eq("batchcooking:#{session.id}:cook:#{stephanie.id}")
      expect(ecriture.kind).to eq("cook_fee")
      expect(ecriture.label).to eq("Batch cooking du 12/09 — 2,5 portions")
    end

    it "ignore un cuisinier à zéro portion — un coup de main sans part" do
      session.servings.create!(member_account: compte_cheveche, portions: 3)
      session.cooks.create!(human: stephanie, portions: 0)
      record

      expect(MemberAccount.find_by(human_id: stephanie.id)).to be_nil
      expect(AccountEntry.where(kind: "cook_fee").count).to eq(0)
    end

    # `Human` porte un `default_scope` sur `status: "active"`. Une personne
    # partie disparaîtrait donc de l'association, et rejouer une session de
    # juin échouerait sur un cuisinier qui a pourtant bien cuisiné.
    it "paie encore un cuisinier qui a quitté le lieu depuis" do
      session.servings.create!(member_account: compte_cheveche, portions: 3)
      session.cooks.create!(human: stephanie, portions: 3)
      record
      stephanie.update_column(:status, "inactive")

      expect { record }.not_to raise_error
      expect(MemberAccount.find_by(human_id: stephanie.id).balance_cents).to eq(-1_050)
    end
  end

  describe "rejeu et modification" do
    it "ne crée rien de plus quand on rejoue" do
      session_de_reference
      record

      expect { record }.not_to change(AccountEntry, :count)
      expect(record.created).to eq(0)
      expect(record.unchanged).to eq(4)
    end

    it "régénère les écritures quand les portions changent" do
      session_de_reference
      record

      session.servings.find_by(member_account: compte_cheveche).update!(portions: 5)
      rapport = record

      expect(rapport.updated).to eq(1)
      expect(compte_cheveche.account_entries.sum(:amount_cents)).to eq(2_500)
      expect(AccountEntry.where(kind: "batchcooking").count).to eq(2)
    end

    it "supprime l'écriture d'un ménage retiré de la session" do
      session_de_reference
      record

      session.servings.find_by(member_account: compte_merle).destroy!
      rapport = record

      expect(rapport.deleted).to eq(1)
      expect(compte_merle.account_entries.count).to eq(0)
    end

    it "garde le prix FIGÉ quand le barème change après coup" do
      session_de_reference
      record
      seed_rate("meal.batchcooking.per_person", 600, active_from: Date.new(2026, 10, 1))
      Pricing::Rates.reset!

      session.servings.find_by(member_account: compte_cheveche).update!(portions: 4)
      record

      charge = compte_cheveche.account_entries.first
      expect(charge.unit_price_cents).to eq(500)
      expect(charge.amount_cents).to eq(2_000)
    end

    it "refuse de toucher une session dont une écriture est verrouillée" do
      session_de_reference
      record
      compte_cheveche.account_entries.first.update!(locked_at: Time.current)

      session.servings.find_by(member_account: compte_cheveche).update!(portions: 5)

      expect { record }.to raise_error(ServiceError, /contre-écriture/)
      expect(compte_cheveche.account_entries.first.amount_cents).to eq(1_500)
    end

    it "laisse rejouer une session verrouillée qui n'a pas changé" do
      session_de_reference
      record
      compte_cheveche.account_entries.first.update!(locked_at: Time.current)

      expect { record }.not_to raise_error
    end
  end

  describe "barème absent" do
    it "refuse plutôt que de facturer zéro" do
      Rate.destroy_all
      Pricing::Rates.reset!
      session.servings.create!(member_account: compte_cheveche, portions: 3)

      expect { record }.to raise_error(ServiceError, /barème/)
    end
  end

  describe "#run" do
    it "attrape l'erreur et rend son message plutôt que de lever" do
      session.servings.create!(member_account: compte_cheveche, portions: 3)
      compte_cheveche.update!(active: false)

      service = described_class.new(session: session)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/désactivé/)
    end
  end
end
