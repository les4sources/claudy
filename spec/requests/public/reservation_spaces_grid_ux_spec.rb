require "rails_helper"

# Epic #234, Phase 3 — parité funnel. Le funnel public rend le MÊME partial que
# le formulaire admin : les gestes de ligne, le résumé en clair et les bornes du
# séjour doivent s'y retrouver à l'identique (décision 7 de l'epic).
RSpec.describe "Public::Reservations — UX de la grille Espaces (epic #234, Phase 3)", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  let(:lundi)    { (Date.today + 60).next_occurring(:monday) }
  let(:vendredi) { lundi + 4 }

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/x"))

    post "/reservation/sejour", params: {
      reservation: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601, adults: 2 }
    }
    get "/reservation/composer"
  end

  it "porte les mêmes gestes de ligne qu'en admin" do
    doc = Nokogiri::HTML(response.body)

    expect(doc.css(%(button[data-action*="public--spaces-calendar#fillRow"])).size).to eq(3)
    expect(doc.css(%(button[data-action*="public--spaces-calendar#clearRow"])).size).to eq(3)
  end

  it "porte le résumé par espace et les bornes du séjour" do
    doc = Nokogiri::HTML(response.body)

    expect(doc.css("[data-summary-for]").map { |l| l["data-summary-for"] })
      .to match_array(%w[grande_salle petite_salle cuisine_pro])
    expect(doc.css("thead th").count { |th| th["class"].to_s.include?("spaces-grid-edge") }).to eq(2)
  end

  it "affiche les tarifs du catalogue, forfait 5 jours compris" do
    expect(response.body).to include("140 €/j · 90 €/soir · 525 € les 5 jours")
    # L'ancienne indication codée en dur dans la vue n'existe plus.
    expect(response.body).not_to include("140€/j · 90€/soir (sem.)")
  end

  # Chaque case reste un vrai `<button>` : elle s'atteint au `Tab` et se change
  # à `Espace` / `Entrée` sans une ligne de JavaScript de plus.
  it "laisse chaque case atteignable au clavier" do
    cases = Nokogiri::HTML(response.body).css("button.funnel-slot")

    expect(cases.size).to be >= 15 # 3 espaces × 5 jours
    expect(cases.map { |b| b["type"] }.uniq).to eq(["button"])
    expect(cases.map { |b| b["tabindex"] }.compact).to be_empty
  end
end
