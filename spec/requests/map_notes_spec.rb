require "rails_helper"

# Epic #348, phase 7 — les notes datées sur la fiche plante : liste
# antéchronologique, ajout inline (date par défaut aujourd'hui), suppression
# (soft-delete), repli des plus anciennes. La section seule est remplacée.
RSpec.describe "Carte du domaine — notes datées d'une plante (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "agent-notes@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:plant) { Plant.create!(name: "Pommier du haut", zone: "Verger") }

  def section(body = response.body)
    Nokogiri::HTML(body).at_css(%([data-plant-section="notes"]))
  end

  it "exige une session Devise" do
    post plant_map_notes_path(plant), headers: turbo, params: { map_note: { body: "Gel" } }
    expect(MapNote.count).to eq(0)
  end

  context "connecté" do
    before { sign_in user }

    it "liste les notes de la plus récente à la plus ancienne, date en clair" do
      plant.map_notes.create!(body: "Floraison", noted_on: Date.new(2026, 4, 12))
      plant.map_notes.create!(body: "Bourgeons gelés", noted_on: Date.new(2026, 5, 3), author: user)

      get plant_path(plant)

      node = section
      expect(node.css("[data-note-id] p").map(&:text)).to eq(["Bourgeons gelés", "Floraison"])
      expect(node.text).to include("3 mai 2026", "12 avril 2026", "Notes datées (2)")
      expect(node.at_css(%(input[name="map_note[noted_on]"]))["value"]).to eq(Date.current.iso8601)
    end

    it "replie les notes au-delà des cinq plus récentes" do
      7.times { |i| plant.map_notes.create!(body: "Note #{i}", noted_on: Date.new(2026, 1, 1) + i) }

      get plant_path(plant)

      node = section
      expect(node.css(%([data-notes="recent"] [data-note-id])).size).to eq(5)
      expect(node.css(%(details [data-notes="older"] [data-note-id])).map { |li| li.at_css("p").text }).to eq(["Note 1", "Note 0"])
      expect(node.text).to include("Voir les 2 notes plus anciennes")
    end

    describe "POST" do
      it "ajoute une note datée d'aujourd'hui par défaut, signée, et remplace la section" do
        travel_to(Time.zone.local(2026, 5, 3, 10)) do
          post plant_map_notes_path(plant), headers: turbo, params: { map_note: { body: "  Bourgeons gelés  " } }
        end

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(plant, :notes)}">))
        note = plant.map_notes.sole
        expect([note.body, note.noted_on, note.author]).to eq(["Bourgeons gelés", Date.new(2026, 5, 3), user])
        expect(section.text).to include("Bourgeons gelés", "3 mai 2026", "Notes datées (1)")
      end

      it "garde la date choisie" do
        post plant_map_notes_path(plant), headers: turbo, params: { map_note: { body: "Taille", noted_on: "2026-02-14" } }
        expect(plant.map_notes.sole.noted_on).to eq(Date.new(2026, 2, 14))
      end

      it "refuse lisiblement (422) une note vide, en gardant la date saisie" do
        post plant_map_notes_path(plant), headers: turbo, params: { map_note: { body: "  ", noted_on: "2026-02-14" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(MapNote.count).to eq(0)
        expect(section.at_css("[role=alert]").text).to include("La note est vide")
        expect(section.at_css(%(input[name="map_note[noted_on]"]))["value"]).to eq("2026-02-14")
      end
    end

    describe "DELETE" do
      it "supprime la note (soft-delete) et remplace la section" do
        note = plant.map_notes.create!(body: "Floraison")

        delete plant_map_note_path(plant, note), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(MapNote.count).to eq(0)
        expect(MapNote.unscoped.find(note.id).deleted_at).to be_present
        expect(section.text).to include("Aucune note pour l'instant")
      end

      it "ne supprime pas la note d'une autre plante" do
        other = Plant.create!(name: "Poirier")
        note = other.map_notes.create!(body: "Floraison")

        expect { delete plant_map_note_path(plant, note), headers: turbo }.to raise_error(ActiveRecord::RecordNotFound)
        expect(note.reload.deleted_at).to be_nil
      end
    end
  end
end
