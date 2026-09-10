require "rails_helper"

# Epic #246 — ce que le batch cooking donne à LIRE, une fois enregistré : la
# ligne sur le décompte du ménage, et le compte personnel du cuisinier.
RSpec.describe "Batch cooking — décompte et compte personnel", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:cheveche) { Household.create!(name: "Chevêche", kind: "resident") }
  let!(:compte_cheveche) { MemberAccount.create!(kind: "household", household: cheveche, name: "Chevêche") }
  let(:stephanie) { Human.create!(name: "Stéphanie") }

  let(:session) { BatchCookingSession.create!(cooked_on: Date.new(2026, 9, 12), label: "Chili") }

  before do
    sign_in user
    %w[meal.batchcooking.per_person meal.batchcooking.cook_volunteering]
      .zip([500, 350]).each do |key, cents|
        rate = Rate.create!(key: key, amount_cents: cents)
        rate.rate_versions.create!(amount_cents: cents, active_from: RateVersion::ORIGIN)
      end
    Pricing::Rates.reset!

    session.servings.create!(member_account: compte_cheveche, portions: 3)
    session.cooks.create!(human: stephanie, portions: 3)
    Finance::RecordBatchCooking.new(session: session).run!
  end

  describe "le décompte du ménage" do
    it "porte la ligne batch cooking et son montant" do
      statement = Finance::IssueStatement.new(member_account: compte_cheveche,
                                              month: Date.new(2026, 9, 1)).run!

      expect(statement.debits_cents).to eq(1_500)
      expect(statement.account_entries.map(&:label)).to include("Batch cooking du 12/09 — 3 portions · Chili")
    end

    it "se lit sur le décompte que le ménage reçoit" do
      statement = Finance::IssueStatement.new(member_account: compte_cheveche,
                                              month: Date.new(2026, 9, 1)).run!

      get public_statement_path(token: statement.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Batch cooking du 12/09 — 3 portions")
      expect(response.body).to include("15,00")
    end
  end

  describe "le compte personnel du cuisinier" do
    let(:compte) { MemberAccount.find_by(human_id: stephanie.id) }

    it "montre ses crédits et dit que le solde est en sa faveur" do
      get finance_account_path(compte)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Batch cooking du 12/09 — 3 portions")
      expect(response.body).to include("En sa faveur")
      expect(response.body).to include("10,50")
    end

    it "ne réclame rien à un compte créditeur" do
      get finance_account_path(compte)

      expect(response.body).not_to include("À régler")
    end

    it "laisse le décompte d'un ménage débiteur parler de ce qu'il doit" do
      get finance_account_path(compte_cheveche)

      expect(response.body).not_to include("En sa faveur")
    end
  end
end
