require "rails_helper"

# Date d'encaissement d'un paiement (Michael 2026-08-20). Le compte bancaire se
# pointe avec du retard : sans date saisissable, un virement reçu le 3 et encodé
# le 17 se lisait au 17. Optionnelle — vide, on retombe sur la date de saisie.
RSpec.describe "Paiements — date d'encaissement", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "date-paiement@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) do
    Customer.create!(email: "date@example.com", first_name: "Dora", last_name: "Datée")
  end

  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.today + 3, departure_date: Date.today + 5,
                 total_amount_cents: 20_000)
  end

  it "propose le champ date dans le formulaire d'ajout de la modale séjour" do
    get stay_path(stay), params: { modal: 1 }

    expect(response.body).to include('name="payment[paid_on]"')
  end

  it "enregistre la date saisie" do
    post stay_payments_path(stay), params: {
      payment: { amount: "120", payment_method: "bank_transfer", status: "paid",
                 paid_on: "2026-08-03" }
    }

    expect(Payment.last.paid_on).to eq(Date.new(2026, 8, 3))
  end

  it "laisse la date vide quand le champ n'est pas rempli, et retombe sur la saisie" do
    post stay_payments_path(stay), params: {
      payment: { amount: "120", payment_method: "cash", status: "paid", paid_on: "" }
    }

    payment = Payment.last
    expect(payment.paid_on).to be_nil
    expect(payment.effective_date).to eq(payment.created_at.to_date)
  end

  it "corrige la date depuis l'édition d'une ligne existante" do
    payment = Payment.create!(stay: stay, amount_cents: 12_000, status: "paid",
                              payment_method: "bank_transfer")

    patch stay_payment_path(stay, payment), params: {
      payment: { amount: "120", payment_method: "bank_transfer", paid_on: "2026-07-29" }
    }

    expect(payment.reload.paid_on).to eq(Date.new(2026, 7, 29))
  end

  it "affiche la date d'encaissement plutôt que la date d'encodage dans le journal" do
    Payment.create!(stay: stay, amount_cents: 12_000, status: "paid",
                    payment_method: "bank_transfer", paid_on: Date.new(2026, 8, 3))

    get payments_path

    expect(response.body).to include("03/08/2026")
    expect(response.body).to include("Encodé le #{Date.today.strftime('%d/%m/%Y')}")
  end
end
