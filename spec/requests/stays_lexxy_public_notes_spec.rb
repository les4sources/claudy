require "rails_helper"

# Issue #312 — bascule Trix → Lexxy.
#
# La régression la plus probable de la bascule : la note publique d'un séjour était
# pré-remplie via `to_trix_html`, un format propre à Trix. Lexxy consomme le HTML
# canonique d'Action Text. Si on avait gardé `to_trix_html`, rouvrir un séjour avec
# une note publique l'aurait ré-affichée vide ou échappée — et aucun test ne l'aurait vu.
RSpec.describe "Séjours — note publique en Lexxy", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-lexxy@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:customer) do
    Customer.create!(email: "lexxy-client@example.com", customer_type: "individual",
                     first_name: "Alice", last_name: "Martin")
  end
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.today + 30, departure_date: Date.today + 32)
  end

  it "rend un éditeur Lexxy, plus un éditeur Trix" do
    get edit_stay_path(stay)

    expect(response.body).to include("<lexxy-editor")
    expect(response.body).not_to include("<trix-editor")
  end

  it "ré-affiche la note publique existante avec sa mise en forme" do
    stay.update!(public_notes: "<p>Arrivée <strong>après 17 h</strong>.</p>")

    get edit_stay_path(stay)

    # Lexxy transporte le contenu dans l'attribut `value` de son élément personnalisé,
    # donc le HTML de la note y arrive échappé une fois — c'est normal et attendu.
    # Ce qui compte : le balisage de la note est bien présent, et pas perdu en route.
    editor = response.body[/<lexxy-editor[^>]*name="stay\[public_notes\]"[^>]*>/]
    expect(editor).to be_present
    expect(editor).to include("&lt;p&gt;Arrivée &lt;strong&gt;après 17 h&lt;/strong&gt;.&lt;/p&gt;")
  end
end
