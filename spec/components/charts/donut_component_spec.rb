require "rails_helper"

# Issue #276 — l'anneau de répartition du CA Accueil. Le point sensible n'est
# pas le dessin mais la part ABSENTE : bar et épicerie valent zéro tant que la
# comptabilité n'est pas encodée, et la page doit le dire.
RSpec.describe Charts::DonutComponent, type: :component do
  DonutSlice = Struct.new(:label, :color, :amount_cents, :state, keyword_init: true) do
    def missing_accounting? = state == :missing_accounting

    def missing_account? = state == :missing_account
  end

  def slice(label, color, amount_cents, state: :present)
    DonutSlice.new(label: label, color: color, amount_cents: amount_cents, state: state)
  end

  let(:slices) do
    [
      slice("Hébergements", "#0d9488", 75_00),
      slice("Salles", "#c026d3", 25_00)
    ]
  end

  it "dessine un arc par part non nulle, plus le cercle de fond" do
    render_inline(described_class.new(slices: slices, year: 2026))

    expect(page).to have_css("svg circle", count: 3)
    expect(page).to have_css("circle[stroke='#0d9488']")
  end

  it "porte le total de l'année au centre de l'anneau" do
    render_inline(described_class.new(slices: slices, year: 2026))

    expect(page.text).to include("Total 2026")
    expect(page.text).to include("100,00 €")
  end

  it "donne montant et part de chaque activité dans la légende" do
    render_inline(described_class.new(slices: slices, year: 2026))

    expect(page.text).to include("75,00 €")
    expect(page.text).to include("75,0%")
    expect(page.text).to include("25,0%")
  end

  it "dit qu'une activité n'est pas encore encodée, au lieu de la taire" do
    render_inline(described_class.new(slices: slices + [slice("Bar", "#7c3aed", 0, state: :missing_accounting)],
                                      year: 2026))

    expect(page.text).to include("Bar")
    expect(page.text).to include("pas encore encodé en comptabilité")
  end

  it "signale un compte comptable introuvable" do
    render_inline(described_class.new(slices: slices + [slice("Épicerie", "#0891b2", 0, state: :missing_account)],
                                      year: 2026))

    expect(page.text).to include("compte comptable introuvable")
  end

  it "distingue une activité à zéro euro de vente d'une activité non encodée" do
    render_inline(described_class.new(slices: slices + [slice("Cuisine", "#ea580c", 0)], year: 2026))

    expect(page.text).to include("Cuisine")
    expect(page.text).not_to include("pas encore encodé en comptabilité")
  end

  it "s'annonce comme une image, avec une description chiffrée" do
    render_inline(described_class.new(slices: slices, year: 2026))

    svg = page.find("svg")
    expect(svg[:role]).to eq("img")
    expect(svg["aria-label"]).to include("Répartition du chiffre d'affaires Accueil 2026")
  end

  it "affiche un état vide lisible, sans perdre les activités non encodées" do
    render_inline(described_class.new(
                    slices: [slice("Hébergements", "#0d9488", 0),
                             slice("Bar", "#7c3aed", 0, state: :missing_accounting)],
                    year: 2019
                  ))

    expect(page.text).to include("Aucun chiffre d'affaires enregistré")
    expect(page.text).to include("pas encore encodé en comptabilité")
    expect(page).to have_no_css("svg")
  end
end
