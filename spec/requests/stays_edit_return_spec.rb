require "rails_helper"

# Retour après l'édition d'un séjour (Michael, 2026-10-18) : enregistrer,
# annuler ou supprimer (2026-10-19) ramène TOUJOURS à la vue d'où le formulaire
# a été ouvert — agenda (modale rouverte via `open_stay`, sauf après
# suppression), liste des séjours, paiements… Le chemin
# vient du `return_to` du lien, sinon du Referer, et reste borné à l'application.
RSpec.describe "Stays — retour à la vue d'origine après édition", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-retour@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging)  { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { (Date.today + 30).next_occurring(:monday) }
  let(:departure) { arrival + 2 }

  let!(:stay) do
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222"
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual")
    builder.run!
    builder.stay
  end

  def update_params(extra = {})
    {
      stay: {
        customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 3, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }
    }.merge(extra)
  end

  def hidden_return_to
    Nokogiri::HTML(response.body).at_css("input[type=hidden][name=return_to]")&.[]("value")
  end

  def cancel_href
    Nokogiri::HTML(response.body).css("a").find { |a| a.text.strip == "Annuler" }&.[]("href")
  end

  describe "GET /stays/:id/edit" do
    it "garde le return_to du lien (agenda, modale à rouvrir)" do
      get edit_stay_path(stay, return_to: "/?date=2026-10-12&open_stay=#{stay.id}")

      expect(hidden_return_to).to eq("/?date=2026-10-12&open_stay=#{stay.id}")
      expect(cancel_href).to eq("/?date=2026-10-12&open_stay=#{stay.id}")
    end

    it "retombe sur le Referer quand le lien n'en porte pas (liste des paiements)" do
      get edit_stay_path(stay), headers: { "Referer" => "http://www.example.com/payments" }

      expect(hidden_return_to).to eq("/payments")
      expect(cancel_href).to eq("/payments")
    end

    it "garde les filtres de la liste des séjours" do
      get edit_stay_path(stay), headers: { "Referer" => "http://www.example.com/stays?filter=balance_due&quarter=2026-Q4" }

      expect(hidden_return_to).to eq("/stays?filter=balance_due&quarter=2026-Q4")
    end

    it "retire `modal` : le fragment de modale n'est pas une page" do
      get edit_stay_path(stay, return_to: "/stays/#{stay.id}?modal=1")

      expect(hidden_return_to).to eq("/stays/#{stay.id}")
    end

    it "refuse un autre domaine, un chemin protocolaire et le formulaire lui-même" do
      [
        "https://evil.example.org/stays",
        "//evil.example.org/stays",
        "/\\evil.example.org",
        "javascript:alert(1)",
        "/stays/#{stay.id}/edit",
        "/bookings/12/edit"
      ].each do |raw|
        get edit_stay_path(stay, return_to: raw)

        expect(hidden_return_to).to be_nil, "accepté à tort : #{raw}"
        expect(cancel_href).to eq(stay_path(stay))
      end
    end

    it "sans origine connue, « Annuler » mène à la fiche du séjour" do
      get edit_stay_path(stay)

      expect(hidden_return_to).to be_nil
      expect(cancel_href).to eq(stay_path(stay))
    end
  end

  describe "PATCH /stays/:id" do
    it "revient à la vue d'origine après enregistrement" do
      patch stay_path(stay), params: update_params(return_to: "/?date=2026-10-12&open_stay=#{stay.id}")

      expect(response).to redirect_to("/?date=2026-10-12&open_stay=#{stay.id}")
      expect(flash[:notice]).to eq("Séjour mis à jour.")
    end

    it "ignore un return_to externe et garde le repli historique" do
      patch stay_path(stay), params: update_params(return_to: "https://evil.example.org/")

      expect(response).to redirect_to(recent_stays_path)
    end

    it "garde le return_to quand l'enregistrement échoue et que le formulaire se réaffiche" do
      params = update_params(return_to: "/payments")
      params[:stay][:departure_date] = (arrival - 1).iso8601
      patch stay_path(stay), params: params

      expect(response).to have_http_status(:unprocessable_entity)
      expect(hidden_return_to).to eq("/payments")
    end
  end

  describe "DELETE /stays/:id" do
    def delete_button_return_to
      Nokogiri::HTML(response.body).css("form").find { |f| f.at_css("button")&.text&.strip == "Supprimer le séjour" }
              &.at_css("input[name=return_to]")&.[]("value")
    end

    it "le bouton « Supprimer » du formulaire emporte la vue d'origine" do
      get edit_stay_path(stay), headers: { "Referer" => "http://www.example.com/payments" }

      expect(delete_button_return_to).to eq("/payments")
    end

    it "revient à la vue d'origine après suppression" do
      delete stay_path(stay), params: { return_to: "/stays?q=Martin" }

      expect(response).to redirect_to("/stays?q=Martin")
      expect(flash[:notice]).to eq("Séjour supprimé.")
    end

    it "ne rouvre pas la modale du séjour supprimé sur l'agenda" do
      delete stay_path(stay), params: { return_to: "/?date=2026-10-12&open_stay=#{stay.id}" }

      expect(response).to redirect_to("/?date=2026-10-12")
    end

    it "ne revient pas sur la fiche du séjour supprimé" do
      delete stay_path(stay), params: { return_to: "/stays/#{stay.id}" }

      expect(response).to redirect_to(recent_stays_path)
    end

    it "sans origine connue, garde le repli historique" do
      delete stay_path(stay)

      expect(response).to redirect_to(recent_stays_path)
    end
  end
end
