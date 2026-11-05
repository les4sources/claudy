require "rails_helper"

# Demi-journée des salles (Michael, 2026-11-03) : « un espace peut être loué à
# la demi-journée ». La grille du site range la demi-journée avec la soirée, au
# même prix (« Demi-journée / Soirée ») — semaine comme week-end. Ce fichier fige
# les huit montants de la grille et la place de la demi-journée dans les règles
# existantes (vendredi, duo, forfaits).
RSpec.describe PricingModel, "demi-journée des salles" do
  let(:monday)   { Date.parse("2026-06-08") }
  let(:friday)   { Date.parse("2026-06-12") }
  let(:saturday) { Date.parse("2026-06-13") }

  def draft(**attrs)
    defaults = { lodging: nil, nights: 0, dogs_count: 0,
                 campings: [], vans: [], halls: [], meals: [], pizza_parties: [] }
    OpenStruct.new(defaults.merge(attrs))
  end

  def quote_for(from, to, slots)
    described_class.quote(draft(arrival_date: from, departure_date: to, space_slots: slots))
  end

  def spaces_cents(from, to, slots) = quote_for(from, to, slots).spaces_cents

  it "suit la grille SEMAINE du site : 70 / 90 / 190 €" do
    { "cuisine_pro" => 7_000, "petite_salle" => 9_000, "grande_salle" => 19_000 }.each do |kind, cents|
      expect(spaces_cents(monday, monday, { kind => ["demi_journee"] })).to eq(cents), kind
    end
  end

  it "suit la grille WEEK-END du site : 95 / 120 / 250 €" do
    { "cuisine_pro" => 9_500, "petite_salle" => 12_000, "grande_salle" => 25_000 }.each do |kind, cents|
      expect(spaces_cents(saturday, saturday, { kind => ["demi_journee"] })).to eq(cents), kind
    end
  end

  it "reste en SEMAINE un vendredi (le week-end ouvre à 18h30)" do
    expect(spaces_cents(friday, friday, { "grande_salle" => ["demi_journee"] })).to eq(19_000)
  end

  it "vaut la colonne « Les deux salles » quand les deux salles sont prises la même demi-journée" do
    both = { "grande_salle" => ["demi_journee"], "petite_salle" => ["demi_journee"] }

    expect(spaces_cents(monday, monday, both)).to eq(25_000)
    expect(spaces_cents(saturday, saturday, both)).to eq(33_500)
  end

  it "nomme la demi-journée dans le devis" do
    labels = quote_for(monday, monday, { "petite_salle" => ["demi_journee"] }).breakdown.map { |l| l[:label] }

    expect(labels.join).to include("demi-journée")
  end

  it "se laisse couvrir par un forfait de journées quand il revient moins cher" do
    # 4 journées + 1 demi-journée à l'unité = 4 × 290 + 190 = 1 350 € ;
    # le forfait 5 jours de la Grande Salle vaut 990 €.
    slots = { "grande_salle" => %w[journee journee journee journee demi_journee] }

    expect(spaces_cents(monday, friday, slots)).to eq(99_000)
  end

  it "suit Paramètres > Tarifs : la ligne « soirée » vaut pour la demi-journée" do
    Rate.create!(key: "hall.petite_salle.soiree", amount_cents: 9_500, label: "Petite Salle — demi-journée / soirée (semaine)")
    Pricing::Rates.reset!

    expect(spaces_cents(monday, monday, { "petite_salle" => ["demi_journee"] })).to eq(9_500)
  ensure
    Pricing::Rates.reset!
  end
end
