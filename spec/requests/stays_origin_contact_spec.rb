require "rails_helper"

# Contact d'origine porté par les réservables (Michael 2026-07-26).
#
# Tout l'historique importé est rattaché au client FOURRE-TOUT faute d'email
# exploitable : le seul nom réel du dossier vit alors sur le Booking /
# SpaceBooking. Sans rappel dans la fiche, l'édition d'un séjour legacy
# n'affiche AUCUN nom.
RSpec.describe "Fiche séjour — contact d'origine", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-origine@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:catch_all) do
    Customer.create!(email: Customer::CATCH_ALL_EMAIL, first_name: "Client", last_name: "Les 4 Sources")
  end

  def stay_for(customer)
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.today + 5, departure_date: Date.today + 7)
  end

  def attach_space_booking(stay, **attrs)
    sb = SpaceBooking.create!({ firstname: "Mailys", lastname: "Buts", group_name: "Mariage",
                                from_date: Date.today + 5, to_date: Date.today + 7 }.merge(attrs))
    StayItem.create!(stay: stay, bookable: sb)
    sb
  end

  context "séjour rattaché au client fourre-tout" do
    let!(:stay) { stay_for(catch_all) }
    before { attach_space_booking(stay) }

    it "remonte le nom et le groupe portés par le réservable" do
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mailys Buts")
      expect(response.body).to include("Mariage")
    end

    it "signale explicitement l'absence de vrai client" do
      get edit_stay_path(stay)
      expect(response.body).to include("aucun vrai client")
    end
  end

  context "séjour rattaché à un vrai client" do
    let!(:customer) do
      Customer.create!(email: "mailys@example.com", first_name: "Mailys", last_name: "Buts")
    end
    let!(:stay) { stay_for(customer) }

    it "n'affiche pas le rappel quand le réservable ne dit rien de plus" do
      attach_space_booking(stay, group_name: nil)
      get edit_stay_path(stay)
      expect(response.body).not_to include("Contact d'origine")
    end

    it "affiche le rappel quand le réservable porte un nom de groupe" do
      attach_space_booking(stay, group_name: "Fanfare communale")
      get edit_stay_path(stay)
      expect(response.body).to include("Contact d'origine")
      expect(response.body).to include("Fanfare communale")
    end
  end

  # Nom AFFICHÉ dans les listes : « Client Les 4 Sources » ne dit rien, on lui
  # préfère le nom de groupe de la réservation d'origine.
  describe "#display_name" do
    it "préfère le nom de groupe d'origine sur un séjour fourre-tout" do
      stay = stay_for(catch_all)
      attach_space_booking(stay, group_name: "Camp louveteaux")
      expect(stay.reload.decorate.display_name).to eq("Camp louveteaux")
    end

    # Forme RÉELLE des données legacy (séjour 1417) : le réservable est
    # soft-deleted mais son StayItem survit. On pose donc `deleted_at` par
    # `update_column` — un `destroy` cascaderait sur l'item et ne reproduirait
    # pas le cas.
    it "va chercher le nom sur un réservable SOFT-DELETED" do
      stay = stay_for(catch_all)
      sb = attach_space_booking(stay, group_name: "Camp supprimé")
      sb.update_column(:deleted_at, Time.current)
      expect(stay.reload.decorate.display_name).to eq("Camp supprimé")
    end

    # Résa OTA : pas de nom de groupe, mais un prénom sur le réservable. C'est
    # ce que le calendrier affiche déjà via `group_or_name` — la liste doit dire
    # la même chose (séjour 1440, « Freya », Airbnb).
    it "retombe sur le prénom du réservable quand il n'y a pas de nom de groupe" do
      stay = stay_for(catch_all)
      attach_space_booking(stay, group_name: nil, firstname: "Freya", lastname: nil)
      expect(stay.reload.decorate.display_name).to eq("Freya")
    end

    it "préfère le nom de GROUPE au nom de la personne quand les deux existent" do
      stay = stay_for(catch_all)
      attach_space_booking(stay, group_name: "Camp louveteaux", firstname: "Freya")
      expect(stay.reload.decorate.display_name).to eq("Camp louveteaux")
    end

    it "garde le nom du client quand il n'est pas un fourre-tout" do
      customer = Customer.create!(email: "vrai@example.com", first_name: "Vrai", last_name: "Client")
      stay = stay_for(customer)
      attach_space_booking(stay, group_name: "Peu importe")
      expect(stay.reload.decorate.display_name).to eq("Vrai Client")
    end

    # Le seul cas où l'on retombe vraiment sur le fourre-tout : aucun réservable,
    # donc aucun nom d'origine à récupérer. Dès qu'un réservable existe, il porte
    # au minimum un prénom (contrainte du modèle).
    it "retombe sur le nom du client quand le séjour n'a aucun réservable" do
      stay = stay_for(catch_all)
      expect(stay.reload.decorate.display_name).to eq("Client Les 4 Sources")
    end
  end

  # Un séjour sans réservable n'a aucun contact d'origine à rappeler : le bloc
  # ne doit pas s'afficher, même sur le fourre-tout.
  context "séjour sans réservable" do
    let!(:stay) { stay_for(catch_all) }

    it "n'affiche aucun rappel (rien à rappeler)" do
      get edit_stay_path(stay)
      expect(response.body).not_to include("Contact d'origine")
    end
  end
end
