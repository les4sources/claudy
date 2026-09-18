require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #244, phase 3 — le relevé de rémunération d'un porteur, et son paiement.
#
# Une prestation tenue portait sa rémunération figée depuis la phase 1 ; rien ne
# la payait. L'invariant qui tient tout : une prestation n'est relevée qu'UNE
# fois — sinon on paie deux fois le même travail.
RSpec.describe "Porteurs — relevé de rémunération (epic #244, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-porteurs@les4sources.be", password: "password123") }
  let!(:entity) { LegalEntity.find_by(name: "Fondation Les 4 Sources") || build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank_general) { build_general_account(code: "550000", name: "Banque") }
  let!(:fee_account) { build_general_account(code: "616000", name: "Rémunérations d'intervenants", klass: 6, nature: "expense") }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:cash_account) { build_cash_account(entity, bank_general) }

  let!(:team) { Team.create!(name: "Transmission") }
  let!(:carrier) { Human.create!(name: "Sébastien", email: "seb@les4sources.be") }
  let!(:experience) { Experience.create!(name: "Initiation vannerie", human: carrier, team: team, duration_hours: 2) }
  let(:customer) { Customer.create!(email: "client-porteur@example.com", first_name: "Léa", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.current - 40, departure_date: Date.current - 38)
  end

  before { sign_in user }

  def slot(on:, exp: experience)
    ExperienceAvailability.create!(experience: exp, available_on: on, starts_at: "10:00", duration_minutes: 120)
  end

  # Une prestation TENUE : confirmée, passée, verdict posé, rémunération figée.
  def held_booking(on: Date.current - 30, exp: experience)
    booking = ExperienceBooking.create!(experience_availability: slot(on: on, exp: exp), stay: stay,
                                        participants: 2, status: "confirmed")
    booking.update_columns(outcome: "held", outcome_recorded_at: Time.current)
    booking.reload
  end

  describe "la sélection" do
    it "ne retient que le tenu, jamais le déjà relevé" do
      tenue = held_booking
      autre = held_booking(on: Date.current - 20)
      ExperienceBooking.create!(experience_availability: slot(on: Date.current - 10), stay: stay,
                                participants: 1, status: "confirmed")

      selection = CarrierStatements::Selection.new(human: carrier)
      expect(selection.bookings).to match_array([tenue, autre])

      CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
      expect(CarrierStatements::Selection.new(human: carrier).bookings).to be_empty
    end

    it "borne la période quand on lui en donne une" do
      vieille = held_booking(on: Date.current - 300)
      recente = held_booking(on: Date.current - 10)

      selection = CarrierStatements::Selection.new(human: carrier, period_from: Date.current - 30, period_to: Date.current)
      expect(selection.bookings).to eq([recente])
      expect(selection.bookings).not_to include(vieille)
    end
  end

  describe "générer" do
    it "produit un brouillon avec ses lignes et son total" do
      held_booking
      held_booking(on: Date.current - 20)

      service = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current)
      statement = service.run!

      expect(statement).to be_draft
      expect(statement.carrier_statement_lines.count).to eq(2)
      expect(statement.total_fee_cents).to eq(statement.carrier_statement_lines.sum(:fee_cents))
      expect(statement.total_fee_cents).to be_positive
      expect(statement.token).to be_present
      expect(statement.posted_at).to be_nil
    end

    it "refuse quand il n'y a rien à relever" do
      service = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current)
      expect(service.run).to be(false)
      expect(service.error_message).to include("Aucune prestation tenue")
    end

    it "refuse un deuxième brouillon" do
      held_booking
      CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!

      held_booking(on: Date.current - 5)
      service = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current)
      expect(service.run).to be(false)
      expect(service.error_message).to include("déjà un relevé en brouillon")
    end

    it "vise le trimestre civil précédent par défaut" do
      from, to = CarrierStatements::Generate.default_period(Date.new(2026, 5, 12))
      expect(from).to eq(Date.new(2026, 1, 1))
      expect(to).to eq(Date.new(2026, 3, 31))
    end

    it "ne relève jamais deux fois la même prestation" do
      tenue = held_booking
      statement = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!

      doublon = CarrierStatementLine.new(carrier_statement: statement, experience_booking: tenue, fee_cents: 100)
      expect(doublon).not_to be_valid
      expect(doublon.errors[:experience_booking_id].join).to include("déjà relevée")
    end
  end

  describe "émettre" do
    let(:statement) do
      held_booking
      held_booking(on: Date.current - 20)
      CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
    end

    it "fige le total, passe l'écriture et envoie le mail" do
      ActionMailer::Base.deliveries.clear

      post issue_finance_carrier_statement_path(statement)

      statement.reload
      expect(statement).to be_issued
      expect(statement.issued_at).to be_present
      expect(statement.posted_at).to be_present
      expect(statement.sent_at).to be_present
      expect(ActionMailer::Base.deliveries.last.to).to eq([carrier.email])

      entry = JournalEntry.unscoped.find_by(source: statement, journal: "purchases")
      expect(entry).to be_present

      charge = entry.journal_lines.select { |l| l.debit_cents.to_i.positive? }
      expect(charge.map { |l| l.general_account.code }.uniq).to eq(["616000"])
      expect(charge.map(&:team).uniq).to eq([team])
      expect(charge.sum(&:debit_cents)).to eq(statement.total_fee_cents)

      credit = entry.journal_lines.select { |l| l.credit_cents.to_i.positive? }
      expect(credit.size).to eq(1)
      expect(credit.first.general_account.code).to eq("440000")
      expect(credit.first.third_party.name).to eq("Sébastien")
    end

    it "ventile la charge par pôle" do
      autre_team = Team.create!(name: "Accueil")
      autre_exp = Experience.create!(name: "Balade contée", human: carrier, team: autre_team, duration_hours: 1)
      held_booking(on: Date.current - 25)
      held_booking(on: Date.current - 15, exp: autre_exp)

      fresh = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
      CarrierStatements::Issue.new(statement: fresh).run!

      entry = JournalEntry.unscoped.find_by(source: fresh, journal: "purchases")
      charges = entry.journal_lines.select { |l| l.debit_cents.to_i.positive? }
      expect(charges.map { |l| l.team&.name }).to match_array(["Transmission", "Accueil"])
    end

    it "est idempotente : ré-émettre ne repasse ni écriture ni mail" do
      CarrierStatements::Issue.new(statement: statement).run!
      ActionMailer::Base.deliveries.clear

      CarrierStatements::Issue.new(statement: statement.reload).run!

      expect(JournalEntry.unscoped.where(source: statement, journal: "purchases").count).to eq(1)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "n'échoue pas quand le porteur n'a pas d'email" do
      carrier.update!(email: nil)
      CarrierStatements::Issue.new(statement: statement).run!

      expect(statement.reload).to be_issued
      expect(statement.sent_at).to be_nil
    end
  end

  describe "l'immuabilité" do
    let(:booking) { held_booking }
    let!(:statement) do
      booking
      CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
    end

    it "fige le verdict d'une prestation relevée" do
      booking.outcome = "no_show"
      expect(booking).not_to be_valid
      expect(booking.errors[:outcome].join).to include("contre-passation")
    end

    it "refuse de supprimer un relevé émis" do
      CarrierStatements::Issue.new(statement: statement).run!

      delete finance_carrier_statement_path(statement)
      follow_redirect!
      expect(response.body).to include("contre-passation")
      expect(CarrierStatement.find_by(id: statement.id)).to be_present
    end

    it "laisse supprimer un brouillon, et rend ses prestations disponibles" do
      delete finance_carrier_statement_path(statement)

      expect(CarrierStatement.find_by(id: statement.id)).to be_nil
      expect(CarrierStatements::Selection.new(human: carrier).bookings).to include(booking)
    end
  end

  describe "« À payer » et le rapprochement" do
    let(:statement) do
      held_booking
      CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
    end

    it "n'y met pas un brouillon" do
      statement
      get finance_payables_path
      expect(response.body).not_to include(statement.reference)
    end

    it "y met un relevé émis, avec sa référence en communication" do
      CarrierStatements::Issue.new(statement: statement).run!

      get finance_payables_path
      expect(response.body).to include(statement.reference)
      expect(response.body).to include("Sébastien")
    end

    it "le solde par rapprochement, et le défait si on retire l'affectation" do
      CarrierStatements::Issue.new(statement: statement).run!

      entry = build_cash_entry(cash_account, amount_cents: -statement.total_fee_cents, label: "Virement Sébastien")
      allocation = entry.cash_allocations.create!(general_account: supplier_account,
                                                  amount_cents: -statement.total_fee_cents,
                                                  legal_entity: entity, document: statement)

      expect(statement.reload).to be_paid
      expect(statement.paid_on).to eq(entry.entry_date)

      allocation.destroy!
      expect(statement.reload).to be_issued
      expect(statement.paid_on).to be_nil
    end
  end

  describe "les écrans" do
    it "liste les porteurs et ce qu'on leur doit" do
      held_booking
      get finance_carrier_statements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sébastien")
      expect(response.body).to include("Générer le relevé")
    end

    it "affiche un relevé et son détail" do
      held_booking
      statement = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!

      get finance_carrier_statement_path(statement)
      expect(response.body).to include("Initiation vannerie")
      expect(response.body).to include(statement.reference)
      expect(CGI.unescapeHTML(response.body)).to include("Émettre le relevé")
    end

    it "ouvre la page à jeton sans connexion" do
      held_booking
      statement = CarrierStatements::Generate.new(human: carrier, period_from: Date.current - 60, period_to: Date.current).run!
      CarrierStatements::Issue.new(statement: statement).run!

      sign_out user
      get public_carrier_statement_path(statement.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sébastien")
      expect(response.body).to include(statement.reference)
    end

    it "renvoie une page d'erreur lisible sur un jeton inconnu" do
      sign_out user
      get public_carrier_statement_path("nimportequoi")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("plus valable")
    end
  end
end
