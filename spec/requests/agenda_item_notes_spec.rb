require "rails_helper"

# Notes de réunion par point de l'ODJ : une note par (point, rassemblement),
# éditée dans une modale distincte du formulaire d'édition du point.
RSpec.describe "Notes des points de l'ODJ", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:human) { Human.create!(name: "Michael", status: "active") }
  let(:user) { User.create!(email: "notes@les4sources.be", password: "password123", human: human) }
  let!(:categorie) { GatheringCategory.create!(name: "Collectif", color: "emerald") }
  let!(:reunion) { build_gathering("2026-10-05 14:00") }
  let!(:suivante) { build_gathering("2026-10-19 14:00") }
  let!(:point) { reunion.agenda_items.create!(title: "Four à bois", author: human) }

  before { sign_in user }

  def build_gathering(starts_at)
    starts = Time.zone.parse(starts_at)
    Gathering.create!(gathering_category: categorie, name: "Réunion", starts_at: starts, ends_at: starts + 2.hours)
  end

  def save_notes(gathering, item, body)
    patch gathering_agenda_item_note_path(gathering, item),
          params: { agenda_item_note: { body: body } },
          as: :turbo_stream
  end

  it "ouvre la modale avec un éditeur de texte riche" do
    get edit_gathering_agenda_item_note_path(reunion, point), headers: { "Turbo-Frame" => "modal" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("lexxy-editor")
    expect(response.body).to include("Notes — Four à bois")
  end

  it "enregistre les notes sur le couple point + rassemblement et les affiche sous le point" do
    save_notes(reunion, point, "<p>On allume samedi.</p>")

    expect(response).to have_http_status(:ok)
    note = point.notes.sole
    expect(note.gathering).to eq(reunion)
    expect(note.body.to_plain_text).to eq("On allume samedi.")
    expect(response.body).to include("On allume samedi.")
  end

  it "met à jour la note existante au lieu d'en créer une seconde" do
    save_notes(reunion, point, "<p>Première version</p>")
    save_notes(reunion, point, "<p>Seconde version</p>")

    expect(point.notes.count).to eq(1)
    expect(point.notes.sole.body.to_plain_text).to eq("Seconde version")
  end

  it "supprime la note quand on vide l'éditeur" do
    save_notes(reunion, point, "<p>À effacer</p>")
    save_notes(reunion, point, "")

    expect(point.notes).to be_empty
  end

  describe "un point reporté" do
    before do
      save_notes(reunion, point, "<p>Discuté à moitié.</p>")
      point.update!(gathering: suivante)
    end

    it "laisse ses notes sur le rassemblement où elles ont été prises" do
      get gathering_path(reunion)

      expect(response.body).to include("Notes des points reportés")
      expect(response.body).to include("Discuté à moitié.")
    end

    it "repart d'une page blanche au rassemblement suivant, avec l'historique en lecture seule" do
      get edit_gathering_agenda_item_note_path(suivante, point), headers: { "Turbo-Frame" => "modal" }

      expect(response.body).to include("Notes des rassemblements précédents")
      expect(response.body).to include("Discuté à moitié.")

      save_notes(suivante, point, "<p>Tranché.</p>")
      expect(point.notes.map { |n| n.gathering_id }).to contain_exactly(reunion.id, suivante.id)
    end
  end
end
