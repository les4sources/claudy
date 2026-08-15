require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le devis reconstruit sert de PROPORTIONS, jamais de montant. Deux moteurs de
# prix ont coexisté dans l'application : re-coter un vieux séjour donnerait un
# total qui n'a jamais été facturé.
RSpec.describe Finance::VentilateStay do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:salles) { build_general_account(code: "700100", name: "Salles", klass: 7, nature: "revenue") }
  let!(:repas) { build_general_account(code: "700200", name: "Repas", klass: 7, nature: "revenue") }
  let!(:activites) { build_general_account(code: "700400", name: "Activités", klass: 7, nature: "revenue") }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }
  let(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 8, 12), departure_date: Date.new(2026, 8, 15))
  end

  before do
    RevenueMapping.create!(category: "lodging", general_account: hebergement)
    RevenueMapping.create!(category: "spaces", general_account: salles)
    RevenueMapping.create!(category: "meals", general_account: repas)
  end

  def stub_quote(lodging:, spaces: 0, meals: 0, camping: 0, van: 0, terrace: 0, hamac: 0, experiences: 0)
    quote = instance_double(PricingModel::Quote, lodging_only_cents: lodging, spaces_cents: spaces,
                                                 meals_cents: meals, camping_cents: camping, van_cents: van,
                                                 terrace_cents: terrace, hamac_cents: hamac,
                                                 experiences_cents: experiences)
    allow(Stays::DraftReconstructor).to receive(:call).with(stay).and_return(:draft)
    allow(PricingModel).to receive(:quote).with(:draft).and_return(quote)
  end

  it "répartit le montant reçu au prorata des catégories du devis" do
    stub_quote(lodging: 126_500, spaces: 116_000, meals: 45_000)

    lignes = described_class.new(stay: stay, amount_cents: 130_000).run!

    expect(lignes.map(&:category)).to contain_exactly("lodging", "spaces", "meals")
    expect(lignes.sum(&:amount_cents)).to eq(130_000)
    expect(lignes.find { |l| l.category == "lodging" }.general_account).to eq(hebergement)
  end

  # L'invariant qui rend le service sûr : quoi qu'ait pu devenir le tarif entre
  # la vente et aujourd'hui, la ventilation somme à l'argent réellement reçu.
  it "somme exactement au montant, même avec des restes de division" do
    stub_quote(lodging: 1, spaces: 1, meals: 1)

    lignes = described_class.new(stay: stay, amount_cents: 100).run!

    expect(lignes.sum(&:amount_cents)).to eq(100)
  end

  it "ne produit aucune ligne pour une catégorie à zéro" do
    stub_quote(lodging: 100_000, spaces: 0, meals: 0)

    lignes = described_class.new(stay: stay, amount_cents: 50_000).run!

    expect(lignes.size).to eq(1)
  end

  it "garde le signe d'un décaissement" do
    stub_quote(lodging: 100_000)

    lignes = described_class.new(stay: stay, amount_cents: -50_000).run!

    expect(lignes.sum(&:amount_cents)).to eq(-50_000)
  end

  # Omettre une catégorie ne perd pas d'argent — c'est pire : sa part est
  # redistribuée aux autres et la ventilation ment sur la nature de la recette.
  it "n'oublie aucune catégorie du devis, activités comprises" do
    RevenueMapping.create!(category: "experiences", general_account: activites)
    stub_quote(lodging: 100_000, experiences: 100_000)

    lignes = described_class.new(stay: stay, amount_cents: 100_000).run!

    expect(lignes.map(&:category)).to contain_exactly("lodging", "experiences")
    expect(lignes.map(&:amount_cents)).to eq([50_000, 50_000])
  end

  it "refuse un devis vide plutôt que de tout mettre sur une ligne muette" do
    stub_quote(lodging: 0)

    expect {
      described_class.new(stay: stay, amount_cents: 50_000).run!
    }.to raise_error(described_class::EmptyQuote, /vide/)
  end

  # L'anti-critère du lot, vérifié en spec : la couche Finances ne calcule
  # jamais un prix, et ce fichier est le seul autorisé à toucher PricingModel.
  it "est le seul service Finances à consommer un moteur de prix" do
    fautifs = Dir[Rails.root.join("app/services/finance/*.rb")].reject { |f| f.end_with?("ventilate_stay.rb") }
                                                               .select { |f| File.read(f).match?(/PricingModel|BookingPrices|Pricing::Catalog/) }

    expect(fautifs).to be_empty
  end
end
