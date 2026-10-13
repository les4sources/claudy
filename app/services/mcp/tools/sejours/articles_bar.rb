module Mcp
  module Tools
    module Sejours
      # Les articles du bar, pour recopier la feuille de consommations d'un
      # groupe (Michael, 2026-10-13) : chaque nom lu sur la photo se rapporte à
      # un article d'ici, par son identifiant.
      class ArticlesBar < Base
        include Commun

        tool "articles_bar",
             title: "Articles du bar et feuille d'un séjour",
             description: "Liste les articles du bar (#id, nom, catégorie, prix public). Avec un séjour : prix à la date " \
                          "du séjour et consommations déjà encodées sur lui. À lire avant encoder_feuille_bar, pour " \
                          "rapporter chaque ligne de la feuille photographiée à un article.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 recherche: { type: "string", description: "Partie du nom d'un article (facultatif)." }
               }
             }

        def call(arguments)
          stay = arguments["sejour"].present? ? sejour!(arguments["sejour"]) : nil
          date = stay ? BarConsumption.price_date_for(stay) : Date.current
          articles = BarConsumption.catalog_items.active.matching(arguments["recherche"])
                                   .includes(:catalog_prices).order(Arel.sql("category NULLS LAST"), :name).to_a

          sections = []
          sections << "#{ligne_sejour(stay)}\n#{feuille(stay)}" if stay
          sections << "Articles du bar (prix au #{date}) :\n#{articles.map { |article| ligne_article(article, date) }.join("\n").presence || 'aucun.'}"
          sections.join("\n\n")
        end

        private

        def ligne_article(article, date)
          prix = BarConsumption.unit_price_for(article, on: date)
          tarif = if prix.nil? then "pas de prix à cette date"
                  elsif BarConsumption.public_price?(article, on: date) then euros(prix)
                  else "#{euros(prix)} (prix sourcier, pas de prix public)"
                  end
          "##{article.id} #{article.name}#{" · #{article.category}" if article.category.present?} : #{tarif}"
        end

        def feuille(stay)
          lignes = stay.bar_consumptions.ordered.to_a
          return "Feuille de bar : rien d'encodé." if lignes.empty?

          "Feuille de bar (#{euros(lignes.sum(&:price_cents))}) :\n" +
            lignes.map { |l| "- #{l.quantity} × #{l.label} (##{l.catalog_item_id}) à #{euros(l.unit_price_cents)}" }.join("\n")
        end
      end
    end
  end
end
