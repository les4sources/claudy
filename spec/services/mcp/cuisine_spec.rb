require "rails_helper"

# Les outils cuisine du connecteur Claude (Michael, 2026-10-05) : les gestes
# de la page Cuisine, avec aperçu puis accord, et le total du séjour qui suit.
RSpec.describe Mcp::Server, "cuisine" do
  let(:admin) { User.create!(email: "michael@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: admin) }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@example.com", status: "active") }
  let!(:anna) { Human.create!(name: "Anna", email: "anna@example.com", status: "active") }
  let(:client) { Customer.create!(first_name: "Camille", last_name: "Martin", email: "camille@example.com") }
  let!(:sejour) do
    Stay.create!(customer: client, source: "manual", status: "confirmed",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end

  before do
    Setting.set("kitchen.repas.default_human_id", steph.id)
    Setting.set("kitchen.coordinator_email", "malau@example.com")
    ActionMailer::Base.deliveries.clear
  end

  def outil(name, arguments, serveur: server)
    serveur.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                     "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]
  def code_de(result) = texte(result)[/confirmation: "([^"]+)"/, 1]

  def confirme(name, arguments, serveur: server)
    apercu = outil(name, arguments, serveur: serveur)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => code_de(apercu)), serveur: serveur)
    expect(resultat[:isError]).to be(false), texte(resultat)
    resultat
  end

  def emails_a = ActionMailer::Base.deliveries.flat_map(&:to)

  def repas(**attrs)
    sejour.meal_orders.create!({ kind: "repas", people: 10, date: Date.current + 20, moment: "midi",
                                 skip_notifications: true }.merge(attrs))
  end

  it "commande deux repas pour un séjour, prévient Stéphanie, recalcule le total et ne commande pas deux fois" do
    arguments = { "sejour" => sejour.id,
                  "prestations" => [{ "type" => "repas", "convives" => 4,
                                      "services" => [{ "date" => (Date.current + 20).iso8601, "moment" => "midi" },
                                                     { "date" => (Date.current + 20).iso8601, "moment" => "soir" }],
                                      "precisions" => "Un végétarien" }] }
    apercu = outil("commander_prestations", arguments)
    expect(texte(apercu)).to include("2 service(s)", "Stéphanie (à valider par la cuisine)", "Email à : steph@example.com")
    expect(sejour.meal_orders.count).to eq(0)

    outil("commander_prestations", arguments.merge("confirmation" => code_de(apercu)))
    expect(sejour.meal_orders.pluck(:moment, :people, :notes)).to contain_exactly(["midi", 4, "Un végétarien"], ["soir", 4, "Un végétarien"])
    expect(sejour.reload.total_amount_cents).to eq(sejour.meal_orders.sum(:price_cents)).and be_positive
    expect(emails_a).to eq(["steph@example.com"])

    rejoue = outil("commander_prestations", arguments)
    expect(rejoue[:isError]).to be(true)
    expect(texte(rejoue)).to include("Déjà commandé")
  end

  it "commande un buffet sans séjour, confié à Anna, donc accepté d'office" do
    confirme("commander_prestations", { "pour_qui" => "École de Spontin",
                                        "prestations" => [{ "type" => "buffet_vege", "convives" => 20, "responsable" => "Anna",
                                                            "services" => [{ "date" => (Date.current + 30).iso8601 }] }] })
    buffet = MealOrder.find_by!(contact_label: "École de Spontin")
    expect(buffet).to have_attributes(kind: "buffet_vege", stay_id: nil, responsible_human: anna, validation: "accepted")

    confirme("rattacher_prestation", { "prestation" => buffet.id, "sejour" => sejour.id })
    expect(buffet.reload.stay).to eq(sejour)
    expect(sejour.reload.total_amount_cents).to eq(buffet.price_cents)
  end

  it "liste ce que la cuisine doit traiter, et la fiche donne la liste de courses" do
    attente = repas
    buffet = sejour.meal_orders.create!(kind: "buffet_viande", people: 10, date: Date.current + 21, skip_notifications: true)
    KitchenProduct.create!(name: "Fromages", unit: "g", quantities: { "buffet_viande" => "50" })

    expect(texte(outil("prestations_cuisine", { "vue" => "cuisine" }))).to include("Prestation ##{attente.id}", "Prestation ##{buffet.id}")
    expect(texte(outil("fiche_prestation", { "prestation" => buffet.id }))).to include("Liste de courses", "Fromages : 500 g")
  end

  it "accepte, puis se désiste avec un motif qui part à la coordination" do
    ligne = repas
    confirme("repondre_prestation", { "prestation" => ligne.id, "decision" => "accepter" })
    expect(ligne.reload).to be_accepted

    expect(outil("repondre_prestation", { "prestation" => ligne.id, "decision" => "refuser" })[:isError]).to be(true)
    confirme("repondre_prestation", { "prestation" => ligne.id, "decision" => "refuser", "raison" => "Stéphanie en congé" })
    expect(ligne.reload).to have_attributes(validation: "refused", refusal_reason: "Stéphanie en congé")
    expect(emails_a).to include("malau@example.com")
  end

  it "remet en attente un repas accepté dont les convives changent" do
    ligne = repas(validation: "accepted", validated_at: Time.current, responsible_human: steph)
    apercu = outil("modifier_prestation", { "prestation" => ligne.id, "convives" => 14 })
    expect(texte(apercu)).to include("REVALIDER")

    confirme("modifier_prestation", { "prestation" => ligne.id, "convives" => 14 })
    expect(ligne.reload).to have_attributes(people: 14, validation: "pending")
    expect(emails_a).to include("steph@example.com")
  end

  it "annule une prestation seulement avec une raison, et le séjour ne la facture plus" do
    ligne = repas
    sejour.recompute_aggregates!
    expect(sejour.reload.total_amount_cents).to eq(ligne.price_cents)

    expect(outil("changer_statut_prestation", { "prestation" => ligne.id, "statut" => "cancelled" })[:isError]).to be(true)
    confirme("changer_statut_prestation", { "prestation" => ligne.id, "statut" => "cancelled", "raison" => "Groupe réduit" })
    expect(ligne.reload).to have_attributes(status: "cancelled", cancellation_reason: "Groupe réduit")
    expect(sejour.reload.total_amount_cents).to eq(0)
  end

  it "confie un repas sans l'accepter à la place de la cuisine" do
    ligne = repas
    confirme("confier_prestation", { "prestation" => ligne.id, "responsable" => "Anna" })
    expect(ligne.reload).to have_attributes(responsible_human: anna, validation: "pending")
  end

  it "règle la cuisine et ses produits" do
    confirme("modifier_reglages_cuisine", { "apero" => { "proposee" => false }, "repas" => { "plafond" => 30 } })
    expect(Kitchen::Config.enabled?("apero")).to be(false)
    expect(Kitchen::Config.max_people("repas")).to eq(30)
    expect(outil("commander_prestations", { "sejour" => sejour.id,
                                            "prestations" => [{ "type" => "apero", "convives" => 5,
                                                                "services" => [{ "date" => (Date.current + 20).iso8601 }] }] })[:isError]).to be(true)

    confirme("enregistrer_produit_cuisine", { "nom" => "Pain", "unite" => "piece", "quantites" => { "buffet_vege" => "0,5" } })
    pain = KitchenProduct.find_by!(name: "Pain")
    expect(pain.quantities).to eq("buffet_vege" => "0.5")
    expect(outil("enregistrer_produit_cuisine", { "produit" => pain.id, "supprimer" => true })[:isError]).to be(true)
    confirme("enregistrer_produit_cuisine", { "produit" => pain.id, "supprimer" => true, "motif" => "doublon" })
    expect(KitchenProduct.exists?(pain.id)).to be(false)

    expect(texte(outil("reglages_cuisine", {}))).to include("Apéros (apero) : RETIRÉE", "plafond 30 convives")
  end

  it "fait le bilan de la période" do
    repas(validation: "accepted", status: "confirmed")
    expect(texte(outil("bilan_cuisine", { "detail" => true }))).to include("Facturé : 150,00 € (1 service(s), 10 couverts)")
  end

  it "reste fermé à un porteur d'activité" do
    porteur = User.create!(email: "anna@example.com", password: "secret123456", human: anna, restricted_to_experiences: true)
    resultat = outil("prestations_cuisine", {}, serveur: described_class.new(user: porteur))
    expect(resultat[:isError]).to be(true)
    expect(texte(resultat)).to include("pas accessible")
  end
end
