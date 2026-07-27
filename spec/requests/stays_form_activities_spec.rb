require "rails_helper"

# Retour Michael 2026-07-27 — le form de séjour proposait TOUS les créneaux
# d'activité à venir, quelles que soient les dates saisies : on se voyait offrir
# un créneau du 7/08 sur un séjour du 30/07. `assignable_availabilities_for` (la
# version fiche) filtrait pourtant déjà par dates ; `prepare_form` ne l'utilisait
# pas et la section vivait HORS du frame rechargé, donc rien ne bougeait quand on
# changeait les dates.
#
# Depuis : la liste vient de `form_assignable_availabilities(draft)`, elle vit
# dans le frame `stay_compose_grids`, et elle protège les créneaux DÉJÀ RETENUS —
# sans quoi leur input disparaîtrait du DOM, ne serait pas soumis, et
# `AdminUpdater#reconcile_experiences!` annulerait l'activité en silence.
RSpec.describe "Stays — créneaux d'activité proposés dans le form", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-form-activites@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:arrivee) { Date.today + 30 }
  let(:depart)  { arrivee + 2 }

  let(:experience) { Experience.create!(name: "Grimpe dans les arbres", fixed_price_cents: 0, price_cents: 3_000) }

  # Un créneau DANS la fenêtre du séjour, un autre bien APRÈS.
  let!(:dedans) do
    ExperienceAvailability.create!(experience: experience, available_on: arrivee + 1, starts_at: "10:00")
  end
  let!(:dehors) do
    ExperienceAvailability.create!(experience: experience, available_on: depart + 10, starts_at: "10:00")
  end

  def recharge(experiences: {})
    post compose_grids_stays_path,
         params: { stay: {
           customer_mode:  "new",
           arrival_date:   arrivee.iso8601,
           departure_date: depart.iso8601,
           adults:         2,
           experiences:    experiences
         } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  # L'`availability_id` est rendu en hidden field : sa présence dans le corps dit
  # que le créneau est proposé à l'écran.
  def propose?(availability)
    response.body.include?(%(value="#{availability.id}"))
  end

  it "ne propose que les créneaux disponibles pendant le séjour" do
    recharge

    expect(propose?(dedans)).to be true
    expect(propose?(dehors)).to be false
  end

  it "suit les dates : un créneau hors fenêtre revient si le séjour s'allonge" do
    post compose_grids_stays_path,
         params: { stay: { customer_mode: "new", arrival_date: arrivee.iso8601,
                           departure_date: (depart + 20).iso8601, adults: 2 } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(propose?(dedans)).to be true
    expect(propose?(dehors)).to be true
  end

  it "conserve un créneau DÉJÀ RETENU même s'il sort de la fenêtre" do
    # Le séjour est raccourci alors que `dehors` porte 4 participants : le
    # supprimer de l'écran le supprimerait de la réservation sans le dire.
    recharge(experiences: { "0" => { availability_id: dehors.id.to_s, participants: "4" } })

    expect(propose?(dehors)).to be true
    expect(response.body).to include(%(value="4"))
  end

  it "laisse tomber un créneau hors fenêtre à zéro participant" do
    recharge(experiences: { "0" => { availability_id: dehors.id.to_s, participants: "0" } })

    expect(propose?(dehors)).to be false
  end
end
