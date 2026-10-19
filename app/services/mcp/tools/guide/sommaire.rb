module Mcp
  module Tools
    module Guide
      # Le sommaire du Guide et sa recherche (Guide::PagesController#index).
      class Sommaire < Base
        include Commun

        tool "guide",
             title: "Le Guide des 4 Sources (sommaire)",
             description: "Le manuel interne du collectif : procédures (ex. « Soumettre une note de frais »), " \
                          "arrivée et départ des membres, coordonnées administratives… Sans argument : le sommaire, " \
                          "chapitres et pages avec leurs identifiants. Avec `recherche` : les pages qui contiennent " \
                          "tous ces mots (titre ou texte). Pour lire une page : page_guide.",
             schema: { properties: { recherche: { type: "string", description: "Mots à chercher dans les pages." } } }

        def call(arguments)
          return recherche(arguments["recherche"].to_s.strip) if arguments["recherche"].present?

          chapitres = GuideChapter.ordered.includes(pages: { last_editor: :human }).to_a
          return "Le Guide est vide : aucun chapitre pour l'instant." if chapitres.empty?

          lignes = chapitres.map do |chapitre|
            entete = "Chapitre ##{chapitre.id} « #{chapitre.title} »#{" — #{chapitre.description}" if chapitre.description.present?}"
            pages = chapitre.pages.map { |page| "  - #{ligne_page(page)}" }
            [entete, *(pages.presence || ["  (aucune page)"])].join("\n")
          end
          "Le Guide des 4 Sources — #{chapitres.size} chapitre(s) :\n\n#{lignes.join("\n\n")}"
        end

        private

        def recherche(texte)
          pages = GuidePage.search(texte).includes(:chapter, last_editor: :human).order(:title).limit(30).to_a
          return "Aucune page du Guide ne contient « #{texte} »." if pages.empty?

          lignes = pages.map { |page| "- #{ligne_page(page)} (chapitre « #{page.chapter.title} »)\n  #{page.excerpt(220)}" }
          "#{pages.size} page(s) pour « #{texte} » :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
