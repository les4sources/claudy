require "rails_helper"

# Section « Comptabilité » de la modale séjour (Michael, 2026-10-19) : au-dessus
# des paiements, le statut de facturation et la note comptable, modifiables sans
# ouvrir le formulaire d'édition.
RSpec.describe "Stays — section Comptabilité de la modale", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-compta-modale@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) do
    Customer.create!(email: "compta-modale@example.com", first_name: "Fanny", last_name: "Facture")
  end

  def create_stay(invoice_status: nil)
    Stay.create!(customer: customer, source: "manual", status: "confirmed", invoice_status: invoice_status,
                 arrival_date: Date.today + 3, departure_date: Date.today + 5)
  end

  describe "la modale" do
    it "montre la section Comptabilité au-dessus des paiements, avec le statut courant" do
      stay = create_stay(invoice_status: "requested")

      get stay_path(stay, modal: 1)

      body = response.body
      expect(body).to include("Comptabilité", "Statut de facturation", update_invoice_status_stay_path(stay))
      expect(body.index("Statut de facturation")).to be < body.index(">Paiements<")
      expect(body).to match(/<option selected="selected" value="requested">À fournir<\/option>/)
    end

    it "sélectionne « Non requise » quand aucune facture n'est attendue" do
      stay = create_stay

      get stay_path(stay, modal: 1)

      expect(response.body).to match(/<option selected="selected" value="none">Non requise<\/option>/)
    end

    it "passe par une liste cherchable" do
      get stay_path(create_stay, modal: 1)

      expect(response.body).to include('data-searchable-select-target="select"')
    end
  end

  describe "PATCH /stays/:id/update_invoice_status" do
    it "pose « À fournir » et rafraîchit la modale en Turbo Stream" do
      stay = create_stay

      patch update_invoice_status_stay_path(stay), params: { stay: { invoice_status: "requested" } }, as: :turbo_stream

      expect(stay.reload.invoice_status).to eq("requested")
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="stay-details-#{stay.id}"))
    end

    it "remet à « Non requise » (nil) depuis la valeur none" do
      stay = create_stay(invoice_status: "sent")

      patch update_invoice_status_stay_path(stay), params: { stay: { invoice_status: "none" } }, as: :turbo_stream

      expect(stay.reload.invoice_status).to be_nil
    end

    it "ignore une valeur inconnue" do
      stay = create_stay(invoice_status: "requested")

      patch update_invoice_status_stay_path(stay), params: { stay: { invoice_status: "paid" } }, as: :turbo_stream

      expect(stay.reload.invoice_status).to eq("requested")
    end

    it "redirige vers la fiche sans Turbo" do
      stay = create_stay

      patch update_invoice_status_stay_path(stay), params: { stay: { invoice_status: "sent" } }

      expect(response).to redirect_to(stay_path(stay))
      expect(stay.reload.invoice_status).to eq("sent")
    end
  end

  describe "note comptable" do
    it "invite à en ajouter une, dans la section Comptabilité" do
      stay = create_stay

      get stay_path(stay, modal: 1)

      body = response.body
      expect(body).to include("Aucune note comptable", update_accounting_notes_stay_path(stay))
      expect(body).to match(/<lexxy-editor[^>]*name="stay\[accounting_notes\]"/)
      expect(body.index("Note comptable")).to be < body.index(">Paiements<")
    end

    it "enregistre la note sans toucher à la note interne" do
      stay = create_stay
      stay.update!(internal_notes: "<p>Clés dans le boîtier.</p>")

      patch update_accounting_notes_stay_path(stay), params: { stay: { accounting_notes: "<p>ASBL Chorale, BE0123.456.789</p>" } }

      expect(response).to redirect_to(stay_path(stay))
      stay.reload
      expect(stay.accounting_note_text).to eq("ASBL Chorale, BE0123.456.789")
      expect(stay.internal_note_text).to eq("Clés dans le boîtier.")
    end

    it "l'affiche dans la modale avec son auteur" do
      stay = create_stay
      PaperTrail.request(whodunnit: user.id.to_s) { stay.update!(accounting_notes: "<p>Facturée le 19/10</p>") }

      get stay_path(stay, modal: 1)

      expect(response.body).to include("Facturée le 19/10", "modifiée par #{user.email}")
      expect(response.body).not_to include("Aucune note comptable")
    end

    it "efface la note quand l'éditeur renvoie du HTML creux" do
      stay = create_stay
      stay.update!(accounting_notes: "<p>À effacer</p>")

      patch update_accounting_notes_stay_path(stay), params: { stay: { accounting_notes: "<div><br></div>" } }

      expect(stay.reload.accounting_note?).to be(false)
      expect(ActionText::RichText.where(record: stay, name: "accounting_notes")).to be_empty
    end
  end
end
