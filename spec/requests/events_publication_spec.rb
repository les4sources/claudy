require "rails_helper"

# Admin des événements : publication sur le site et duplication.
RSpec.describe "Événements — publication et duplication", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "editrice@les4sources.be", password: "password123") }
  let!(:category) { EventCategory.create!(name: "Parties", color: "amber") }
  let!(:event) do
    Event.create!(name: "Pizza party", event_category: category,
                  starts_at: Time.zone.parse("2026-09-18 18:30"), ends_at: Time.zone.parse("2026-09-18 22:00"),
                  summary: "Le four est chaud.", location: "La grange")
  end

  before { sign_in user }

  it "publie puis dépublie depuis la fiche, en gardant le slug" do
    post publish_event_path(event)
    expect(response).to redirect_to(event_path(event))
    expect(event.reload).to be_published
    expect(event.slug).to eq("pizza-party-septembre-2026")

    get event_path(event)
    expect(response.body).to include("www.les4sources.be/evenements/pizza-party-septembre-2026")
    expect(response.body).to include("Dépublier")

    delete unpublish_event_path(event)
    expect(response).to redirect_to(event_path(event))
    expect(event.reload).not_to be_published
    expect(event.slug).to eq("pizza-party-septembre-2026")
  end

  it "accepte un slug choisi à la publication" do
    post publish_event_path(event), params: { slug: "pizza-party-rentree" }
    expect(event.reload.slug).to eq("pizza-party-rentree")
  end

  it "ouvre un formulaire de création prérempli, sans dates, quand on duplique" do
    get duplicate_event_path(event)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("copie de « Pizza party »")
    expect(response.body).to include(%(value="Pizza party"))
    expect(response.body).to include(%(value="Le four est chaud."))
    expect(response.body).to include(%(value="La grange"))
    expect(response.body).to include(%(name="event[duplicate_of_id]"))
    expect(response.body).to include(%(value="#{event.id}"))
    expect(response.body).not_to include("2026-09-18")
    expect(Event.count).to eq(1)
  end

  it "filtre l'index par état de publication" do
    Event.create!(name: "Fête publiée", event_category: category,
                  starts_at: Time.zone.parse("2026-10-01 18:00"), ends_at: Time.zone.parse("2026-10-01 22:00"),
                  published_at: Time.current)

    get events_path(state: "published")
    expect(response.body).to include("Fête publiée")
    expect(response.body).not_to include("Pizza party")

    get events_path(state: "draft")
    expect(response.body).to include("Pizza party")
    expect(response.body).not_to include("Fête publiée")
  end
end
