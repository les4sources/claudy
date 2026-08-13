require "rails_helper"

# Issue #160 — écrans Décomptes, page publique à jeton, règlements.
RSpec.describe "Finances > Décomptes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let!(:account) do
    MemberAccount.create!(kind: "household", household: household, name: "Chevêche",
                          contact_email: "chevêche@les4sources.be")
  end

  def add_entry(date, cents)
    account.account_entries.create!(entry_date: date, amount_cents: cents, label: "Conso bar")
  end

  describe "écran admin" do
    before { sign_in user }

    it "propose par défaut les comptes au solde non nul" do
      add_entry(Date.new(2026, 7, 10), 1500)

      get finance_statements_path(month: "2026-07")

      expect(response.body).to include("Chevêche")
      expect(response.body).to include("À émettre")
    end

    # Envoyer « tu dois 0,00 € » à quinze personnes chaque mois est le meilleur
    # moyen de faire ignorer le décompte de celui qui doit vraiment quelque chose.
    it "écarte les soldes nuls sauf demande explicite" do
      get finance_statements_path(month: "2026-07")
      expect(response.body).not_to include("À émettre")

      get finance_statements_path(month: "2026-07", include_zero: "1")
      expect(response.body).to include("À émettre")
    end

    it "émet les décomptes sélectionnés" do
      add_entry(Date.new(2026, 7, 10), 1500)

      expect {
        post issue_finance_statements_path(month: "2026-07"), params: { member_account_ids: [account.id] }
      }.to change(AccountStatement, :count).by(1)

      expect(AccountStatement.last.closing_balance_cents).to eq(1500)
    end

    it "signale le refus quand les récurrents manquent, sans rien émettre" do
      Rate.create!(key: "dome.monthly_flat", amount_cents: 5000, unit: "cents")
          .rate_versions.create!(amount_cents: 5000, active_from: Date.new(2023, 1, 1))
      RecurringCharge.create!(member_account: account, label: "Dôme", basis: "flat",
                              rate_key: "dome.monthly_flat", starts_on: Date.new(2023, 1, 1))

      expect {
        post issue_finance_statements_path(month: "2026-07"), params: { member_account_ids: [account.id] }
      }.not_to change(AccountStatement, :count)

      follow_redirect!
      expect(response.body).to include("pas générées").or include("ne sont pas générées")
    end
  end

  describe "envoi et relance" do
    before { sign_in user }

    let(:statement) do
      add_entry(Date.new(2026, 7, 10), 1500)
      Finance::IssueStatement.new(member_account: account, month: "2026-07").run!
    end

    it "envoie le décompte et le marque envoyé" do
      expect {
        post send_email_finance_statement_path(statement)
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(statement.reload.sent_at).to be_present
      expect(ActionMailer::Base.deliveries.last.subject).to include("SRC-")
    end

    # Le code dans l'objet, pour qu'un copier-coller paresseux produise quand
    # même une communication exploitable.
    it "porte le mois, le montant et le code dans l'objet" do
      post send_email_finance_statement_path(statement)

      sujet = ActionMailer::Base.deliveries.last.subject
      expect(sujet).to include("juillet 2026")
      expect(sujet).to include(account.code)
      expect(sujet).to match(/15,00/)
    end

    it "incrémente le compteur de relances" do
      post send_email_finance_statement_path(statement)

      expect {
        post remind_finance_statement_path(statement)
      }.to change { statement.reload.reminders_count }.by(1)
    end

    it "refuse d'envoyer à un compte sans email plutôt que d'échouer en silence" do
      account.update!(contact_email: nil)

      expect {
        post send_email_finance_statement_path(statement)
      }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe "page publique à jeton" do
    let(:statement) do
      add_entry(Date.new(2026, 7, 10), 1500)
      Finance::IssueStatement.new(member_account: account, month: "2026-07").run!
    end

    # Le lien du mail doit s'ouvrir sur le téléphone d'un sourcier qui n'a pas
    # de compte Claudy.
    it "s'ouvre SANS session" do
      get public_statement_path(statement.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("15,00")
      expect(response.body).to include(account.code)
    end

    it "renvoie 404 sur un jeton inconnu" do
      get public_statement_path("jeton-bidon")

      expect(response).to have_http_status(:not_found)
    end

    # Le montant affiché est le montant GELÉ, pas un recalcul : c'est toute la
    # raison d'être du décompte.
    it "affiche le montant figé même si une écriture est ajoutée après coup" do
      statement
      account.account_entries.create!(entry_date: Date.new(2026, 7, 28), amount_cents: 9999, label: "Après coup")

      get public_statement_path(statement.token)

      expect(response.body).to include("15,00")
      expect(response.body).not_to include("114,99")
    end
  end

  describe "règlements" do
    before { sign_in user }

    it "crée UNE écriture négative et le règlement qui la documente" do
      add_entry(Date.new(2026, 7, 10), 1500)

      expect {
        post finance_account_settlements_path(account), params: {
          settlement: { amount: "15,00", received_on: "2026-08-02", method: "cash",
                        received_channel: "grocery_box", reference: "SRC-0001" }
        }
      }.to change(AccountEntry, :count).by(1).and change(AccountSettlement, :count).by(1)

      expect(account.reload.balance_cents).to eq(0)
      expect(AccountEntry.last.amount_cents).to eq(-1500)
    end

    # « 20 € dans la caisse de l'épicerie pour le bar » doit rester lisible six
    # mois plus tard.
    it "porte le canal de réception dans le libellé quand ce n'est pas la banque" do
      post finance_account_settlements_path(account), params: {
        settlement: { amount: "20,00", received_on: "2026-08-02", method: "cash", received_channel: "grocery_box" }
      }

      expect(AccountEntry.last.label).to include("épicerie")
    end
  end

  describe "sans authentification" do
    it "redirige l'écran admin vers la connexion" do
      get finance_statements_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
