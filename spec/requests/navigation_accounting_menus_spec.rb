require "rails_helper"

# La sous-navigation Comptabilité en MENUS (Michael, 2026-09-20).
#
# Regrouper dix-neuf entrées dans quatre menus fait gagner une ligne, mais crée
# un risque qui n'existait pas quand tout était à plat : une entrée peut
# disparaître du menu sans que personne s'en aperçoive — l'écran reste
# accessible par son URL, et plus personne ne le trouve. D'où les verrous
# ci-dessous, qui tiennent le recensement plutôt que l'apparence.
RSpec.describe "Menus de la sous-navigation Comptabilité", type: :request do
  let(:user) { User.create!(email: "menus@les4sources.be", password: "password123") }

  before { sign_in user }

  def subnav = Nokogiri::HTML(response.body).at_css("#subnav-accounting")

  def bouton(titre) = subnav.css("button").find { |b| b.text.include?(titre) }

  # Une entrée de menu porte son libellé PUIS une ligne d'explication
  # (2026-10-17) : on la reconnaît à son premier `span`.
  def entree(libelle) = subnav.css("a").find { |a| (a.at_css("span") || a).text.strip == libelle }

  describe "l'état « vous êtes ici »" do
    # Le menu refermé, le bouton du groupe est le SEUL repère : s'il ne
    # s'allume pas, la barre ne dit plus où l'on se trouve.
    it "allume le bouton du groupe qui contient l'écran courant" do
      get finance_ledger_path

      expect(bouton("États")["class"]).to include("text-4s-main")
      expect(bouton("Fournisseurs")["class"]).to include("text-gray-500")
    end

    it "allume aussi l'entrée elle-même, à l'intérieur du menu" do
      get finance_ledger_path

      expect(entree("Grand livre")["class"]).to include("text-4s-main")
    end

    it "allume une entrée directe sans passer par un menu" do
      get finance_cash_entries_path

      expect(entree("Trésorerie")["class"]).to include("text-4s-main")
    end

    # La caisse mobilise trois contrôleurs (feuille, motifs, comptages) : elle
    # doit rester allumée sur les trois, pas seulement sur la feuille.
    it "reste allumée sur les écrans satellites d'une entrée" do
      get finance_cash_motifs_path

      expect(bouton("Banque & caisse")["class"]).to include("text-4s-main")
      expect(entree("Caisse")["class"]).to include("text-4s-main")
    end
  end

  # Le libellé seul ne dit rien à qui démarre (2026-10-17) : chaque entrée de
  # menu porte une ligne qui dit à quoi elle sert.
  it "explique chaque entrée de menu en une ligne" do
    get finance_accounting_path

    sans_explication = subnav.css("ul[id^='subnav-accounting-'] a").reject { |a| a.css("span").size == 2 }
    expect(sans_explication.map(&:text)).to be_empty
  end

  it "mène au guide depuis le bout de la barre" do
    get finance_ledger_path

    expect(entree("Guide")["href"]).to eq(finance_guide_path)
  end

  describe "le recensement des écrans" do
    # Les écrans qu'on atteint DEPUIS un autre écran, jamais depuis la barre.
    # Ajouter un contrôleur ici est une décision : « on ne le cherche pas, on y
    # tombe ». Tout le reste doit avoir son entrée, sans quoi il n'est plus
    # atteignable qu'en tapant son URL.
    SANS_ENTREE = %w[
      finance/allocation_suggestions
      finance/cash_allocations
      finance/stripe_fee_invoices
    ].freeze

    before { Rails.application.eager_load! }

    # Le helper ne fait qu'appeler des `*_path` : une classe qui l'inclut avec
    # les url_helpers suffit à lire la structure, sans monter une vue.
    # (`extend` sur une instance ne suffit pas — les url_helpers s'installent à
    # l'inclusion dans une CLASSE.)
    NavProbe = Class.new do
      include Rails.application.routes.url_helpers
      include AccountingNavHelper
    end

    def nav = NavProbe.new

    def recenses
      entrees = nav.accounting_nav_direct + nav.accounting_nav_groups.flat_map(&:last) + [nav.accounting_nav_guide]
      entrees.flat_map(&:last)
    end

    def ecrans_de_comptabilite
      Finance.constants.map { |c| Finance.const_get(c) }
             .select { |k| k.is_a?(Class) && k < Finance::AccountingBaseController }
             .map(&:controller_path)
    end

    it "donne une entrée de barre à chaque écran de comptabilité" do
      expect(ecrans_de_comptabilite - SANS_ENTREE - recenses).to be_empty
    end

    # L'inverse compte autant : une entrée qui pointe un contrôleur disparu
    # laisse un lien mort dans un menu qu'on n'ouvre qu'une fois par mois.
    it "ne recense aucun contrôleur qui n'existe plus" do
      expect(recenses - ecrans_de_comptabilite).to be_empty
    end
  end
end
