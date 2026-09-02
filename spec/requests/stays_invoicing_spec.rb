require "rails_helper"

# Demande de FACTURE portée par le séjour (Michael 2026-09-02).
#
# Le seul chemin qui posait `invoice_status` (`Bookable#set_invoice_status`, via
# le `invoice_wanted` du formulaire Booking) a disparu avec ce formulaire :
# depuis l'epic #81 tout se saisit sur le séjour, et rien n'y permettait plus de
# dire « ce client veut une facture ». Le séjour porte donc la colonne, le
# formulaire la saisit, et la file Accueil > Facturation la traite.
RSpec.describe "Séjours — demande de facture", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "factu-sejour@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) do
    Customer.create!(email: "facture@example.com", first_name: "Fanny", last_name: "Facture")
  end

  def stay(invoice_status: nil, total_cents: 45_000)
    @stay ||= Stay.create!(customer: customer, source: "manual", status: "confirmed",
                           arrival_date: Date.today + 3, departure_date: Date.today + 5,
                           total_amount_cents: total_cents, invoice_status: invoice_status)
  end

  describe "formulaire séjour" do
    it "propose les trois états de facture" do
      get edit_stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Facturation")
      expect(response.body).to include(%(name="stay[invoice_status]"))
      expect(response.body).to include("Non requise")
      expect(response.body).to include("À fournir")
    end

    it "présélectionne l'état courant du séjour" do
      get edit_stay_path(stay(invoice_status: "requested"))

      expect(response.body).to include(%(<option selected="selected" value="requested">))
    end
  end

  # Édition RÉELLE : le formulaire séjour poste toute sa composition, pas le seul
  # champ facture — l'`AdminUpdater` refuse un séjour sans dates ni hébergement.
  describe "PATCH /stays/:id" do
    let!(:lodging)  { Lodging.create!(name: "La Hulotte", summary: "gîte") }
    let(:arrival)   { Date.today + 30 }
    let(:departure) { Date.today + 32 }

    def edited_stay(invoice_status: nil)
      draft = Reservations::Draft.new(
        lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
        adults: 2, first_name: "Fanny", last_name: "Facture",
        email: "facture@example.com", phone: "0470111222"
      )
      builder = Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual")
      builder.run!
      builder.stay.tap { |s| s.update!(invoice_status: invoice_status) }
    end

    def update_params(edited, overrides = {})
      {
        stay: {
          customer_mode: "existing", customer_id: edited.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "pending"
        }.merge(overrides)
      }
    end

    it "pose la demande dès la CRÉATION du séjour" do
      post stays_path, params: {
        stay: {
          customer_mode: "new",
          new_customer: { first_name: "Fanny", last_name: "Facture", email: "facture@example.com", phone: "0470111222" },
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "pending", invoice_status: "requested"
        }
      }

      expect(Stay.order(:created_at).last.invoice_status).to eq("requested")
    end

    it "pose « à fournir » depuis le formulaire" do
      edited = edited_stay

      patch stay_path(edited), params: update_params(edited, invoice_status: "requested")

      expect(edited.reload.invoice_status).to eq("requested")
    end

    it "retire la demande quand on repasse sur « non requise »" do
      edited = edited_stay(invoice_status: "requested")

      patch stay_path(edited), params: update_params(edited, invoice_status: "")

      expect(edited.reload.invoice_status).to be_nil
    end

    # Le champ ne doit JAMAIS faire échouer l'enregistrement d'un séjour : une
    # valeur forgée laisse le statut existant en place, sans erreur.
    it "ignore une valeur hors liste sans casser l'enregistrement" do
      edited = edited_stay(invoice_status: "requested")

      patch stay_path(edited), params: update_params(edited, invoice_status: "n_importe_quoi")

      expect(response).to have_http_status(:found)
      expect(edited.reload.invoice_status).to eq("requested")
    end
  end

  describe "file Accueil > Facturation" do
    it "liste le séjour marqué « à fournir »" do
      stay(invoice_status: "requested")

      get invoicing_path

      expect(response.body).to include("Fanny Facture")
      expect(response.body).to include("Séjour")
      expect(response.body).to include(%(href="#{stay_path(stay)}"))
    end

    it "n'y fait pas figurer un séjour sans facture demandée" do
      stay

      get invoicing_path

      expect(response.body).not_to include("Fanny Facture")
    end

    # Une facture, une ligne : un séjour porteur du statut parle pour ses
    # réservables, dont l'import legacy a pu marquer le même statut.
    it "masque le réservable du séjour déjà listé" do
      stay(invoice_status: "requested")
      Booking.create!(firstname: "T", group_name: "Chorale de Dinant", adults: 2,
                      from_date: Date.today + 3, to_date: Date.today + 5,
                      status: "confirmed", invoice_status: "requested",
                      price_cents: 15_000, stay: stay)

      get invoicing_path

      expect(Invoicing::Queue.new.requested.size).to eq(1)
      expect(response.body).not_to include("Chorale de Dinant")
    end

    it "marque la facture du séjour comme envoyée" do
      stay(invoice_status: "requested")

      patch invoicing_status_path(kind: "stay", id: stay.id), params: { invoice_status: "sent" }

      expect(response).to redirect_to(invoicing_path)
      expect(stay.reload.invoice_status).to eq("sent")
    end

    # `undefined_tier` s'appuie sur la colonne `tier`, que le séjour n'a pas :
    # le bloc « tarif non tranché » doit rester sur les seuls réservables.
    it "ne fait pas exploser le bloc « sans tarif défini »" do
      stay(invoice_status: "requested")

      expect { get invoicing_path }.not_to raise_error
      expect(response).to have_http_status(:ok)
    end
  end

  describe "fiche séjour" do
    it "affiche le badge de facture quand une facture est attendue" do
      get stay_path(stay(invoice_status: "requested"))

      expect(response.body).to include("À fournir")
    end

    it "n'affiche aucun badge sur un séjour sans facture" do
      get stay_path(stay)

      expect(response.body).not_to include("Facture à fournir")
    end
  end
end
