require "rails_helper"

# Les outils séjours du connecteur Claude (Michael, 2026-10-05) : ce que fait
# la fiche séjour, et rien qui ne s'écrive sans aperçu puis accord.
RSpec.describe Mcp::Server, "séjours" do
  let(:user) { User.create!(email: "michael@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }
  let!(:hulotte) do
    Lodging.create!(name: "La Hulotte", price_night_cents: 48_500).tap do |gite|
      gite.rooms << Room.create!(name: "Chambre 1", level: 1)
      gite.rooms << Room.create!(name: "Chambre 2", level: 1)
    end
  end
  let!(:client) do
    Customer.create!(first_name: "Camille", last_name: "Martin", email: "camille@example.com", phone: "+32470112233")
  end
  let(:arrivee) { Date.current + 30 }
  let(:depart) { Date.current + 32 }
  let!(:sejour) do
    builder = Reservations::Builder.new(
      draft: Reservations::Draft.new(lodging_id: hulotte.id, arrival_date: arrivee, departure_date: depart, dogs_count: 0,
                                     adults: 4, customer_id: client.id, first_name: "Camille", last_name: "Martin",
                                     email: client.email),
      admin: true, status: "pending", source: "manual"
    )
    builder.run!
    builder.stay
  end

  before { ActionMailer::Base.deliveries.clear }

  def outil(name, arguments)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                    "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]
  def code_de(result) = texte(result)[/confirmation: "([^"]+)"/, 1]

  # Aperçu, puis la même demande confirmée.
  def confirme(name, arguments)
    apercu = outil(name, arguments)
    expect(apercu[:isError]).to be(false), texte(apercu)
    outil(name, arguments.merge("confirmation" => code_de(apercu)))
  end

  describe "lecture" do
    it "retrouve un séjour par le nom du client et en donne la fiche" do
      liste = texte(outil("chercher_sejours", { "recherche" => "Martin" }))
      expect(liste).to include("##{sejour.id}", "Camille Martin", "en attente")

      fiche = outil("fiche_sejour", { "sejour" => "##{sejour.id}" })
      expect(fiche[:isError]).to be(false), texte(fiche)
      expect(texte(fiche)).to include("camille@example.com", "La Hulotte", "Aucun paiement")
    end

    it "dit qu'un gîte pré-confirmé n'est plus libre, et chiffre un devis sans rien écrire" do
      Stays::QuickStatusUpdater.new(stay: sejour, status: "confirmed").run
      dispo = texte(outil("disponibilites", { "du" => arrivee.iso8601, "au" => depart.iso8601 }))
      expect(dispo).to include("La Hulotte (##{hulotte.id}) : PRIS (séjours ##{sejour.id})")

      expect do
        devis = texte(outil("devis_sejour", { "hebergement" => "hulotte", "arrivee" => arrivee.iso8601, "depart" => depart.iso8601 }))
        expect(devis).to include("Total :", "n'est PAS libre")
      end.not_to change(Stay, :count)
    end

    it "cherche un client par son téléphone" do
      expect(texte(outil("chercher_clients", { "recherche" => "470 11 22 33" }))).to include("##{client.id} Camille Martin")
    end
  end

  describe "écriture" do
    it "crée un séjour seulement après confirmation, et refuse de le recréer" do
      arguments = { "client" => client.id.to_s, "hebergement" => "La Hulotte",
                    "arrivee" => (arrivee + 10).iso8601, "depart" => (arrivee + 12).iso8601, "adultes" => 2,
                    "note_interne" => "Arrivée tardive" }
      apercu = nil
      expect { apercu = outil("creer_sejour", arguments) }.not_to change(Stay, :count)
      expect(texte(apercu)).to include("APERÇU", "Aucun email au client")

      expect { outil("creer_sejour", arguments.merge("confirmation" => code_de(apercu))) }.to change(Stay, :count).by(1)
      nouveau = Stay.order(:id).last
      expect(nouveau.internal_note_text).to include("Arrivée tardive")
      expect(PaperTrail::Version.where(item: nouveau).last.whodunnit).to start_with("claude:michael@example.com")

      rejoue = outil("creer_sejour", arguments.merge("confirmation" => code_de(apercu)))
      expect(rejoue[:isError]).to be(true)
      expect(Stay.count).to eq(2)
    end

    it "confirme un séjour et l'annonce au client" do
      apercu = outil("changer_statut_sejour", { "sejour" => sejour.id, "statut" => "confirmed" })
      expect(texte(apercu)).to include("partira à camille@example.com")
      expect(sejour.reload.status).to eq("pending")

      resultat = outil("changer_statut_sejour", { "sejour" => sejour.id, "statut" => "confirmed", "confirmation" => code_de(apercu) })
      expect(resultat[:isError]).to be(false), texte(resultat)
      expect(sejour.reload.status).to eq("confirmed")
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include("camille@example.com")
    end

    it "enregistre un paiement, recalcule le reste dû, et ne l'enregistre pas deux fois" do
      montant = (sejour.total_amount_cents / 100.0).round(2)
      arguments = { "sejour" => sejour.id, "montant" => montant, "methode" => "bank_transfer" }
      apercu = outil("enregistrer_paiement_sejour", arguments)
      expect(texte(apercu)).to include("→ 0,00 €")
      expect(sejour.payments.count).to eq(0)

      outil("enregistrer_paiement_sejour", arguments.merge("confirmation" => code_de(apercu)))
      expect(sejour.reload.payment_status).to eq("paid")
      expect(outil("enregistrer_paiement_sejour", arguments.merge("confirmation" => code_de(apercu)))[:isError]).to be(true)
      expect(sejour.payments.count).to eq(1)
    end

    it "complète la note interne sans écraser l'existante" do
      sejour.update!(internal_notes: Stays::InternalNote.to_html("Végétariens"))
      confirme("noter_sejour", { "sejour" => sejour.id, "texte" => "Deux chiens finalement" })
      expect(sejour.reload.internal_note_text).to include("Végétariens", "Deux chiens finalement")
    end

    it "décale un séjour en gardant le reste de sa composition" do
      nouvelle_arrivee = arrivee + 7
      apercu = outil("modifier_sejour", { "sejour" => sejour.id, "arrivee" => nouvelle_arrivee.iso8601,
                                          "depart" => (nouvelle_arrivee + 2).iso8601 })
      expect(texte(apercu)).to include("Avant :", "Après :")
      expect(sejour.reload.arrival_date).to eq(arrivee)

      resultat = outil("modifier_sejour", { "depart" => (nouvelle_arrivee + 2).iso8601, "sejour" => sejour.id,
                                            "arrivee" => nouvelle_arrivee.iso8601, "confirmation" => code_de(apercu) })
      expect(resultat[:isError]).to be(false), texte(resultat)
      expect(sejour.reload.arrival_date).to eq(nouvelle_arrivee)
      expect(sejour.bookables.grep(Booking).first.lodging).to eq(hulotte)
    end

    it "refuse une demande et prévient le client avec le motif" do
      confirme("refuser_sejour", { "sejour" => sejour.id, "raison_client" => "Le gîte est en travaux" })
      expect(sejour.reload.status).to eq("canceled")
      expect(sejour.internal_note_text).to include("Le gîte est en travaux")
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include("camille@example.com")
    end

    it "pré-confirme une demande : acompte en attente et lien de paiement au client" do
      confirme("preconfirmer_sejour", { "sejour" => sejour.id, "acompte" => "100" })
      expect(sejour.reload.status).to eq("pre_confirmed")
      expect(sejour.payments.pending.sum(:amount_cents)).to eq(10_000)
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include("camille@example.com")
    end

    it "refuse une demande de modification du client, motif à l'appui" do
      demande = StayChangeRequest.create!(stay: sejour, draft_snapshot: Stays::DraftReconstructor.new(sejour).to_draft.to_h,
                                          new_total_cents: sejour.total_amount_cents, delta_cents: 0)
      sans_motif = outil("traiter_demande_modification", { "sejour" => sejour.id, "decision" => "refuser" })
      expect(sans_motif[:isError]).to be(true)

      confirme("traiter_demande_modification", { "sejour" => sejour.id, "decision" => "refuser", "raison_client" => "Complet" })
      expect(demande.reload).to have_attributes(status: "refused", refusal_reason: "Complet")
    end

    it "corrige la fiche d'un client" do
      confirme("modifier_client", { "client" => "camille@example.com", "telephone" => "+32 470 99 88 77", "ville" => "Yvoir" })
      expect(client.reload.address_city).to eq("Yvoir")
    end

    it "ne supprime un séjour qu'avec un motif" do
      sans_motif = outil("supprimer_sejour", { "sejour" => sejour.id })
      expect(sans_motif[:isError]).to be(true)

      confirme("supprimer_sejour", { "sejour" => sejour.id, "motif" => "doublon du séjour saisi par Malau" })
      expect(Stay.find_by(id: sejour.id)).to be_nil
    end
  end
end
