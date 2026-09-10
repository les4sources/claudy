require "rails_helper"

# Issue #276 — le graphe en barres empilées. Ce qui se vérifie ici, c'est que
# tous les chiffres du dessin se retrouvent en toutes lettres dans la légende :
# un graphe sans infobulle ne dit rien à qui ne peut pas le voir.
RSpec.describe Charts::StackedBarsComponent, type: :component do
  Serie = Struct.new(:label, :color, :monthly_cents, :total_cents, keyword_init: true) unless defined?(Serie)

  def serie(label, color, monthly_euros)
    cents = monthly_euros.map { |euros| euros * 100 }
    Serie.new(label: label, color: color, monthly_cents: cents, total_cents: cents.sum)
  end

  let(:series) do
    [
      serie("La Chevêche", "#0d9488", [100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200]),
      serie("La Hulotte", "#7c3aed", [0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    ]
  end

  it "dessine un rectangle par mois renseigné et par série" do
    render_inline(described_class.new(series: series, year: 2026))

    expect(page).to have_css("svg rect", count: 3)
  end

  it "donne à chaque série sa couleur" do
    render_inline(described_class.new(series: series, year: 2026))

    expect(page).to have_css("rect[fill='#0d9488']", count: 2)
    expect(page).to have_css("rect[fill='#7c3aed']", count: 1)
  end

  it "porte les douze mois en abscisse" do
    render_inline(described_class.new(series: series, year: 2026))

    expect(page).to have_css("svg text", text: "J", minimum: 1)
    expect(page.text).to include("Revenus des réservations confirmées de 2026")
  end

  it "met dans la légende le total et la part de chaque série" do
    render_inline(described_class.new(series: series, year: 2026))

    expect(page.text).to include("La Chevêche")
    expect(page.text).to include("300,00 €")
    expect(page.text).to include("85,7%")
    expect(page.text).to include("14,3%")
  end

  it "s'annonce comme une image, avec une description chiffrée" do
    render_inline(described_class.new(series: series, year: 2026))

    svg = page.find("svg")
    expect(svg[:role]).to eq("img")
    expect(svg["aria-label"]).to include("Revenus d'hébergement de 2026")
    expect(svg["aria-label"]).to include("La Chevêche 300,00 €")
  end

  it "défile dans son propre conteneur plutôt que d'élargir la page" do
    render_inline(described_class.new(series: series, year: 2026))

    expect(page).to have_css(".overflow-x-auto svg")
  end

  it "affiche un état vide lisible quand rien n'a été réservé" do
    render_inline(described_class.new(series: [], year: 2026))

    expect(page.text).to include("Aucun revenu d'hébergement enregistré")
    expect(page).to have_no_css("svg")
  end

  it "considère comme vide une année où toutes les séries valent zéro" do
    render_inline(described_class.new(series: [serie("La Chevêche", "#0d9488", Array.new(12, 0))],
                                      year: 2026))

    expect(page.text).to include("Aucun revenu d'hébergement enregistré")
  end
end
