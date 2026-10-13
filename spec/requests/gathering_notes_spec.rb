require "rails_helper"

# La fiche d'un rassemblement ne montre qu'un extrait des notes, en texte
# brut ; la note mise en forme s'ouvre dans la modale Turbo.
RSpec.describe "Notes d'un rassemblement", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "notes@les4sources.be", password: "password123") }
  let(:categorie) { GatheringCategory.create!(name: "Collectif", color: "emerald") }
  let(:long_text) { "Mot " * 200 }
  let(:gathering) do
    Gathering.create!(gathering_category: categorie, name: "Réunion",
                      starts_at: Time.zone.parse("2026-10-05 14:00"),
                      ends_at: Time.zone.parse("2026-10-05 16:00"),
                      notes: "<h1>Tour de météo</h1><p><strong>Important</strong> #{long_text}</p><p>Fin de la note</p>")
  end

  before { sign_in user }

  it "n'affiche sur la fiche qu'un extrait sans mise en forme, avec le lien vers la note" do
    get gathering_path(gathering)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("<strong>Important</strong>")
    expect(response.body).not_to include("Fin de la note")
    expect(response.body).to include("Tour de météo")
    expect(response.body).to include("Lire la note complète")
    expect(response.body).to include(notes_gathering_path(gathering))
  end

  it "rend la note complète, mise en forme, dans la modale" do
    get notes_gathering_path(gathering), headers: { "Turbo-Frame" => "modal" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<turbo-frame id="modal">')
    expect(response.body).to include("<strong>Important</strong>")
    expect(response.body).to include("Fin de la note")
  end

  it "n'affiche pas le bloc Notes quand il n'y a pas de note" do
    gathering.update!(notes: nil)

    get gathering_path(gathering)

    expect(response.body).not_to include("Lire la note complète")
  end
end
