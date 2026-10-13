require "rails_helper"

# « Afficher les semaines précédentes » (bug 2026-10-13) : c'était un lien vers
# « #dashboard-calendar ». Une fois l'ancre dans l'URL (premier clic, puis
# rechargement ou retour sur l'agenda), Turbo traitait le clic comme une visite :
# la page se rechargeait et re-masquait les semaines passées. Le déplieur est
# désormais un bouton, qui ne navigue jamais.
RSpec.describe "Calendrier — déplier les semaines précédentes", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "agenda@les4sources.be", password: "password123") }

  before { sign_in user }

  it "rend un bouton qui déplie sur place, sans lien vers une ancre" do
    travel_to Date.new(2026, 10, 13) do
      get "/"
    end

    expect(response).to have_http_status(:ok)
    toggler = Nokogiri::HTML(response.body).at_css("[data-dashboard-calendar-target='pastWeeksToggler']")
    expect(toggler).to be_present

    button = toggler.at_css("button")
    expect(button.text).to include("Afficher les semaines précédentes")
    expect(button["type"]).to eq("button")
    expect(button["data-action"]).to eq("dashboard-calendar#showPastWeeks")
    expect(toggler.at_css("a[href*='#dashboard-calendar']")).to be_nil
  end
end
