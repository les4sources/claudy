require "rails_helper"

# Rendu des pages admin touchées par la publication sur le site : un
# formulaire Slim qui casse ne se voit qu'en le rendant.
RSpec.describe "Pages admin de la publication", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "editrice@les4sources.be", password: "password123") }
  let!(:category) { EventCategory.create!(name: "Parties", color: "amber", pole: "convivialite") }
  let!(:event) do
    Event.create!(name: "Pizza party", event_category: category,
                  starts_at: Time.zone.parse("2026-09-18 18:30"), ends_at: Time.zone.parse("2026-09-18 22:00"))
  end
  let!(:experience) { Experience.create!(name: "Bain d'ânes", summary: "Un moment apaisant", published_at: Time.current) }

  before { sign_in user }

  it "rend le formulaire d'événement avec les champs publics et le slug proposé" do
    get edit_event_path(event)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Résumé public", "Description publique", "Image de couverture", "Adresse publique (slug)")
    expect(response.body).to include(%(value="pizza-party-septembre-2026"))

    get new_event_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("duplicate_of_id")
  end

  it "rend la fiche et le formulaire d'une activité publiée avec son adresse figée" do
    get experience_path(experience)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Publiée", "www.les4sources.be/catalogue/bain-d-anes", "Dépublier")

    get edit_experience_path(experience)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/catalogue/bain-d-anes", "figée depuis la publication")
  end

  it "publie et dépublie une activité" do
    draft = Experience.create!(name: "Tour du projet")
    post publish_experience_path(draft)
    expect(response).to redirect_to(experience_path(draft))
    expect(draft.reload.slug).to eq("tour-du-projet")
    expect(draft).to be_published

    delete unpublish_experience_path(draft)
    expect(draft.reload).not_to be_published
  end

  it "rend les pages des catégories avec la couleur hex et le pôle" do
    get event_categories_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("background-color: #d97706", "Convivialité")

    get edit_event_category_path(category)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(type="color"), %(name="event_category[pole]"), "Vie collective")

    get event_category_path(category)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("#d97706", "Convivialité", "parties")
  end
end
