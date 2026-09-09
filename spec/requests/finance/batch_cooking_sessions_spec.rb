require "rails_helper"

# Epic #246 — l'écran Finances > Batch cooking.
RSpec.describe "Finances > Batch cooking", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "steph@les4sources.be", password: "password123") }

  let(:cheveche) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:merle) { Household.create!(name: "Merle", kind: "resident") }
  let!(:compte_cheveche) { MemberAccount.create!(kind: "household", household: cheveche, name: "Chevêche") }
  let!(:compte_merle) { MemberAccount.create!(kind: "household", household: merle, name: "Merle") }

  let(:stephanie) { Human.create!(name: "Stéphanie") }
  let!(:membre_stephanie) do
    HouseholdMember.create!(household: cheveche, name: "Stéphanie", kind: "adult",
                            human: stephanie, started_on: Date.new(2024, 1, 1))
  end
  # Un enfant qui cuisine mais qui n'existe pas encore comme personne : le cas
  # que l'écran doit refuser en disant quoi faire.
  let!(:membre_lou) do
    HouseholdMember.create!(household: cheveche, name: "Lou", kind: "child",
                            started_on: Date.new(2024, 1, 1))
  end

  before do
    sign_in user
    seed_rate("meal.batchcooking.per_person", 500)
    seed_rate("meal.batchcooking.cook_volunteering", 350)
    Pricing::Rates.reset!
  end

  def seed_rate(key, cents)
    rate = Rate.find_or_create_by!(key: key) { |r| r.amount_cents = cents }
    rate.rate_versions.create!(amount_cents: cents, active_from: RateVersion::ORIGIN)
  end

  def payload(servings: {}, cooks: {}, cooked_on: "2026-09-12", notes: nil)
    { batch_cooking_session: { cooked_on: cooked_on, notes: notes },
      servings: servings, cooks: cooks }
  end

  describe "GET /finance/batch_cooking_sessions/new" do
    it "propose chaque compte de ménage actif et chaque membre présent" do
      get new_finance_batch_cooking_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("servings[#{compte_cheveche.id}]")
      expect(response.body).to include("servings[#{compte_merle.id}]")
      expect(response.body).to include("cooks[#{membre_stephanie.id}][selected]")
      expect(response.body).to include("cooks[#{membre_lou.id}][portions]")
    end

    it "montre le ménage en sous-titre et signale un enfant sans personne" do
      get new_finance_batch_cooking_session_path

      expect(response.body).to include("Chevêche")
      expect(response.body).to include("à créer comme personne")
      expect(response.body).to include(new_human_path(name: "Lou"))
    end

    it "câble l'aperçu en direct sur les deux tarifs du jour" do
      get new_finance_batch_cooking_session_path

      expect(response.body).to include('data-batch-cooking-serving-price-cents-value="500"')
      expect(response.body).to include('data-batch-cooking-cook-price-cents-value="350"')
    end

    it "ne propose pas un compte désactivé" do
      compte_merle.update!(active: false)

      get new_finance_batch_cooking_session_path

      expect(response.body).not_to include("servings[#{compte_merle.id}]")
    end
  end

  describe "POST /finance/batch_cooking_sessions" do
    it "enregistre la session et pose ses écritures" do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3", compte_merle.id => "2" },
                           cooks: { membre_stephanie.id => { selected: "1", portions: "5" } })

      expect(response).to redirect_to(finance_batch_cooking_sessions_path)
      session = BatchCookingSession.last
      expect(session.cooked_on).to eq(Date.new(2026, 9, 12))
      expect(session.total_portions).to eq(5)
      expect(compte_cheveche.account_entries.sum(:amount_cents)).to eq(1_500)
      expect(compte_merle.account_entries.sum(:amount_cents)).to eq(1_000)
      expect(MemberAccount.find_by(human_id: stephanie.id).balance_cents).to eq(-1_750)
    end

    it "ignore une famille laissée vide" do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3", compte_merle.id => "" })

      expect(BatchCookingSession.last.servings.count).to eq(1)
      expect(compte_merle.account_entries.count).to eq(0)
    end

    it "refuse un cuisinier qui n'existe pas comme personne, et dit quoi faire" do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3" },
                           cooks: { membre_lou.id => { selected: "1", portions: "3" } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to include("Lou").and include("pas encore comme personne")
      expect(BatchCookingSession.count).to eq(0)
      expect(AccountEntry.count).to eq(0)
    end

    it "refuse un ménage servi dont le compte est désactivé" do
      compte_merle.update!(active: false)

      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_merle.id => "2" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(BatchCookingSession.count).to eq(0)
      expect(AccountEntry.count).to eq(0)
    end
  end

  describe "PATCH /finance/batch_cooking_sessions/:id" do
    let(:session) do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3" },
                           cooks: { membre_stephanie.id => { selected: "1", portions: "3" } })
      BatchCookingSession.last
    end

    it "régénère les écritures quand les portions changent" do
      patch finance_batch_cooking_session_path(session),
            params: payload(servings: { compte_cheveche.id => "5" },
                            cooks: { membre_stephanie.id => { selected: "1", portions: "5" } })

      expect(response).to redirect_to(finance_batch_cooking_sessions_path)
      expect(compte_cheveche.account_entries.sum(:amount_cents)).to eq(2_500)
      expect(MemberAccount.find_by(human_id: stephanie.id).balance_cents).to eq(-1_750)
      expect(AccountEntry.count).to eq(2)
    end

    it "refuse la modification quand une écriture est verrouillée" do
      seance = session
      compte_cheveche.account_entries.first.update!(locked_at: Time.current)

      patch finance_batch_cooking_session_path(seance),
            params: payload(servings: { compte_cheveche.id => "5" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to include("contre-écriture")
      expect(compte_cheveche.account_entries.first.amount_cents).to eq(1_500)
    end

    it "rouvre la session avec ses portions déjà saisies" do
      get edit_finance_batch_cooking_session_path(session)

      expect(response.body).to include("value=\"3\"")
      expect(response.body).to include("cooks[#{membre_stephanie.id}][selected]")
    end
  end

  describe "GET /finance/batch_cooking_sessions" do
    it "liste les sessions avec leurs totaux facturé et dû" do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3" }, notes: "Soupes et curry",
                           cooks: { membre_stephanie.id => { selected: "1", portions: "3" } })

      get finance_batch_cooking_sessions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Soupes et curry")
      expect(response.body).to include("15,00")
      expect(response.body).to include("10,50")
    end
  end

  describe "DELETE /finance/batch_cooking_sessions/:id" do
    it "emporte les écritures de la session" do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3" })
      seance = BatchCookingSession.last

      delete finance_batch_cooking_session_path(seance)

      expect(AccountEntry.count).to eq(0)
      expect(BatchCookingSession.count).to eq(0)
    end

    it "refuse quand une écriture est rattachée à un décompte émis" do
      post finance_batch_cooking_sessions_path,
           params: payload(servings: { compte_cheveche.id => "3" })
      seance = BatchCookingSession.last
      compte_cheveche.account_entries.first.update!(locked_at: Time.current)

      delete finance_batch_cooking_session_path(seance)

      expect(flash[:alert]).to include("contre-écriture")
      expect(BatchCookingSession.count).to eq(1)
      expect(AccountEntry.count).to eq(1)
    end
  end
end
