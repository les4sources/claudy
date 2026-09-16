require "rails_helper"

# Issue #313 — la note interne d'un séjour devient du texte riche.
#
# Deux écrans la saisissent : le formulaire d'édition complet et l'édition en
# place de la modale (turbo-frame). Les deux doivent rendre un éditeur Lexxy, et
# `PATCH update_notes` doit savoir faire la différence entre une note vidée et un
# éditeur qui renvoie du HTML creux.
RSpec.describe "Séjours — note interne en texte riche", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-note@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) do
    Customer.create!(email: "note-client@example.com", customer_type: "individual",
                     first_name: "Alice", last_name: "Martin")
  end
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.today + 30, departure_date: Date.today + 32)
  end

  describe "formulaire d'édition" do
    it "rend un éditeur de texte riche pour la note interne, avec sa pastille" do
      get edit_stay_path(stay)

      expect(response.body).to match(/<lexxy-editor[^>]*name="stay\[internal_notes\]"/)
      expect(response.body).to include("jamais visible du client")
      expect(response.body).not_to include(%(name="stay[notes]"))
    end

    it "ré-affiche la note interne existante avec sa mise en forme" do
      stay.update!(internal_notes: "<p>Clés dans le <strong>boîtier</strong>.</p>")

      get edit_stay_path(stay)

      editor = response.body[/<lexxy-editor[^>]*name="stay\[internal_notes\]"[^>]*>/]
      expect(editor).to include("&lt;strong&gt;boîtier&lt;/strong&gt;")
    end
  end

  describe "modale du séjour" do
    it "rend la note en texte riche, en écriture manuscrite" do
      stay.update!(internal_notes: "<p>Le mot laissé sur le comptoir.</p>")

      get stay_path(stay)

      expect(response.body).to include("font-caveat")
      expect(response.body).to include("Le mot laissé sur le comptoir.")
      expect(response.body).to match(/<lexxy-editor[^>]*name="stay\[internal_notes\]"/)
    end

    it "invite à en ajouter une quand il n'y en a pas" do
      get stay_path(stay)

      expect(response.body).to include("Aucune note interne")
    end
  end

  describe "PATCH /stays/:id/update_notes" do
    it "enregistre une note mise en forme" do
      patch update_notes_stay_path(stay), params: { stay: { internal_notes: "<p>Sans <em>gluten</em>.</p>" } }

      expect(response).to redirect_to(stay_path(stay))
      expect(stay.reload.internal_notes.body.to_html).to include("<em>gluten</em>")
    end

    # LE piège : un éditeur vidé ne renvoie pas "" mais du HTML creux. Sans le
    # test de vacuité, « effacer la note » la remplirait de balises invisibles.
    it "efface la note quand l'éditeur est vidé" do
      stay.update!(internal_notes: "<p>À effacer.</p>")

      patch update_notes_stay_path(stay), params: { stay: { internal_notes: "<div><br></div>" } }

      expect(stay.reload).not_to be_internal_note
      expect(ActionText::RichText.where(record: stay, name: "internal_notes")).to be_empty
    end

    it "ne touche pas à la note publique" do
      stay.update!(public_notes: "<p>Arrivée dès 15 h.</p>")

      patch update_notes_stay_path(stay), params: { stay: { internal_notes: "<p>Interne.</p>" } }

      expect(stay.reload.public_notes.body.to_plain_text).to include("Arrivée dès 15 h")
    end
  end
end
