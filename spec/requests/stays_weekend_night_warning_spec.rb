require "rails_helper"

# Epic #260, phase 1 — hypothèse de la décision 3 : côté ADMIN la règle de la
# nuit de week-end seule AVERTIT mais ne bloque pas. Malau saisit ce qu'elle a
# accepté au téléphone ; l'app n'a pas à lui interdire son exception.
RSpec.describe "Séjours admin — nuit de week-end seule (epic #260)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-weekend@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:cheveche) do
    lodging = Lodging.create!(name: "La Chevêche", summary: "gîte")
    lodging.rooms << Room.create!(name: "Chambre 1", code: "CH1", level: 1)
    lodging
  end

  let(:vendredi_octobre) { Date.new(2026, 10, 16) } # haute saison

  it "enregistre le séjour malgré la nuit de vendredi isolée" do
    expect {
      post stays_path, params: {
        stay: {
          customer_mode: "new",
          new_customer: { first_name: "Groupe", last_name: "Weekend", email: "weekend@example.com" },
          arrival_date: vendredi_octobre.iso8601, departure_date: (vendredi_octobre + 1).iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: cheveche.id, status: "confirmed"
        }
      }
    }.to change(Stay, :count).by(1)

    # Aucune brique ne sait vendre cette nuit : le devis ne l'invente pas.
    expect(Stay.order(:created_at).last.total_amount_cents).to eq(0)
  end
end
