require "rails_helper"

# Les outils activités du connecteur Claude (Michael, 2026-10-05) : les gestes
# des écrans activités, dans le périmètre de l'utilisateur, avec aperçu puis accord.
RSpec.describe Mcp::Server, "activités" do
  let(:admin) { User.create!(email: "michael@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: admin) }
  let!(:porteuse) { Human.create!(name: "Porteuse Anna", email: "anna@example.com", status: "active") }
  let!(:anes) do
    Experience.create!(name: "Balade avec les ânes", human: porteuse, fixed_price_cents: 4000, price_cents: 1500,
                       duration_hours: 2, max_participants: 10)
  end
  let(:client) { Customer.create!(first_name: "Camille", last_name: "Martin", email: "camille@example.com") }
  let!(:sejour) do
    Stay.create!(customer: client, status: "confirmed", arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end
  let!(:creneau) do
    ExperienceAvailability.create!(experience: anes, available_on: Date.current + 21, starts_at: "10:00", duration_minutes: 120)
  end

  before { ActionMailer::Base.deliveries.clear }

  def outil(name, arguments, serveur: server)
    serveur.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                     "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments, serveur: server)
    apercu = outil(name, arguments, serveur: serveur)
    expect(apercu[:isError]).to be(false), texte(apercu)
    outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]), serveur: serveur)
  end

  it "liste les activités et la fiche avec ses créneaux" do
    expect(texte(outil("chercher_activites", {}))).to include("##{anes.id} Balade avec les ânes", "Porteuse Anna")
    expect(texte(outil("fiche_activite", { "activite" => "ânes" }))).to include("Créneau ##{creneau.id}", "0 inscrit(s)")
  end

  it "inscrit un séjour à une activité, la valide en prévenant le client, et le total suit" do
    apercu = outil("ajouter_activite_sejour", { "sejour" => sejour.id, "creneau" => creneau.id, "participants" => 3 })
    expect(texte(apercu)).to include("0,00 € → 85,00 €", "Le porteur devra la valider")
    expect(sejour.experience_bookings.count).to eq(0)

    confirme("ajouter_activite_sejour", { "sejour" => sejour.id, "creneau" => creneau.id, "participants" => 3 })
    resa = sejour.experience_bookings.last
    expect(resa).to be_pending
    expect(sejour.reload.total_amount_cents).to eq(8_500)

    expect(texte(outil("reservations_activites", {}))).to include("Réservation ##{resa.id}")
    confirme("valider_reservation_activite", { "reservation" => resa.id })
    expect(resa.reload).to be_confirmed
    expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include("camille@example.com")
  end

  it "refuse une réservation avec son motif" do
    resa = ExperienceBooking.create!(experience_availability: creneau, stay: sejour, participants: 2)
    confirme("refuser_reservation_activite", { "reservation" => resa.id, "raison_client" => "Les ânes sont malades" })
    expect(resa.reload).to have_attributes(status: "refused", refusal_reason: "Les ânes sont malades")
  end

  it "déclare la tenue d'une activité passée, pas d'une activité à venir" do
    passe = ExperienceAvailability.create!(experience: anes, available_on: Date.current - 3, starts_at: "10:00", duration_minutes: 120)
    tenue = ExperienceBooking.create!(experience_availability: passe, stay: sejour, participants: 2, status: "confirmed")
    a_venir = ExperienceBooking.create!(experience_availability: creneau, stay: sejour, participants: 2, status: "confirmed")

    expect(outil("declarer_tenue", { "reservations" => [a_venir.id], "tenue" => "held" })[:isError]).to be(true)
    confirme("declarer_tenue", { "reservations" => [tenue.id], "tenue" => "held" })
    expect(tenue.reload).to be_held
  end

  it "ouvre un créneau, et ne supprime pas un créneau qui porte des réservations" do
    confirme("creer_creneau", { "activite" => anes.id, "date" => (Date.current + 40).iso8601, "heure" => "14:00" })
    expect(anes.experience_availabilities.count).to eq(2)

    ExperienceBooking.create!(experience_availability: creneau, stay: sejour, participants: 2)
    expect(outil("supprimer_creneau", { "creneau" => creneau.id })[:isError]).to be(true)
  end

  it "crée une activité et la publie" do
    confirme("enregistrer_activite", { "nom" => "Atelier pain", "porteur" => "Anna", "prix_par_personne" => "12,50",
                                       "duree_heures" => 3 })
    atelier = Experience.find_by!(name: "Atelier pain")
    expect(atelier).to have_attributes(human: porteuse, price_cents: 1250)

    confirme("publier_activite", { "activite" => atelier.id, "action" => "publier" })
    expect(atelier.reload.published_at).to be_present
  end

  it "garde un porteur dans son périmètre" do
    autre = Experience.create!(name: "Yoga", fixed_price_cents: 1000)
    porteur = User.create!(email: "anna@example.com", password: "secret123456", human: porteuse, restricted_to_experiences: true)
    serveur = described_class.new(user: porteur)

    expect(texte(outil("chercher_activites", {}, serveur: serveur))).not_to include("Yoga")
    expect(outil("fiche_activite", { "activite" => autre.id }, serveur: serveur)[:isError]).to be(true)
    expect(outil("enregistrer_activite", { "nom" => "Mon atelier" }, serveur: serveur)[:isError]).to be(true)
  end
end
