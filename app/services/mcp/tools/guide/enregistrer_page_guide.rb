module Mcp
  module Tools
    module Guide
      # Créer une page du Guide, la réécrire, la renommer ou la déplacer
      # (Guide::PagesController : create, update ; glisser-déposer du sommaire).
      class EnregistrerPageGuide < Ecriture
        include Commun

        tool "enregistrer_page_guide",
             title: "Écrire une page du Guide",
             description: "Sans `page` : crée une page dans `chapitre` (titre et contenu). Avec `page` : remplace ce qui " \
                          "est donné — `contenu` remplace TOUT le texte (lis la page avec page_guide d'abord ; pour " \
                          "changer quelques mots, préfère remplacer_texte_guide), `titre` la renomme, `chapitre` et " \
                          "`position` la déplacent. Chaque modification du texte ou du titre devient une version de " \
                          "la page, signée de ton compte, avec le motif comme note. Contenu : #{MARKDOWN}",
             schema: {
               properties: {
                 page: PAGE,
                 chapitre: CHAPITRE,
                 titre: { type: "string" },
                 contenu: { type: "string", description: "Le texte complet de la page, en Markdown." },
                 position: POSITION
               }
             }

        private

        def planifier(arguments)
          page = arguments["page"].present? ? page!(arguments["page"]) : nil
          chapitre = arguments["chapitre"].present? ? chapitre!(arguments["chapitre"]) : page&.chapter
          raise Error, "Pour créer une page, donne son chapitre (voir guide)." if chapitre.nil?

          titre = arguments["titre"].to_s.strip.presence
          contenu = arguments.key?("contenu") ? arguments["contenu"].to_s.gsub("\r\n", "\n").rstrip : nil
          position = arguments["position"].presence&.to_i
          raise Error, "Une nouvelle page demande un titre." if page.nil? && titre.nil?
          if page && titre.nil? && contenu.nil? && chapitre == page.chapter && position.nil?
            raise Error, "Rien à changer : donne un titre, un contenu, un chapitre ou une position."
          end

          resume = page ? resume_modification(page, chapitre, titre, contenu, position) : resume_creation(chapitre, titre, contenu)
          Plan.new(resume: resume,
                   empreinte: [page && [page.id, page.updated_at.to_f, Digest::SHA256.hexdigest(page.body)], chapitre.id,
                               titre, contenu && Digest::SHA256.hexdigest(contenu), position],
                   donnees: { page: page&.id, chapitre: chapitre.id, titre: titre, contenu: contenu, position: position })
        end

        def appliquer(plan)
          donnees = plan.donnees
          page = donnees[:page] ? GuidePage.find(donnees[:page]) : GuidePage.new
          attributs = { guide_chapter_id: donnees[:chapitre], title: donnees[:titre], body: donnees[:contenu],
                        summary: @motif.presence || (page.new_record? ? "Création" : nil) }
          service = ::Guide::SavePage.new(page, user: user, source: "mcp")
          raise Error, page.errors.full_messages.to_sentence unless service.call(attributs)

          if donnees[:position]
            pages = GuidePage.where(guide_chapter_id: page.guide_chapter_id).ordered.to_a
            GuidePage.reorder!(page.chapter, ordre_avec(pages, page, donnees[:position]))
          end
          "#{ligne_page(page.reload)} — chapitre « #{page.chapter.title} » · #{page.revisions.size} version(s)\n" \
            "Adresse : #{lien_page(page)}"
        end

        def resume_creation(chapitre, titre, contenu)
          [
            "CRÉER la page « #{titre} » dans le chapitre ##{chapitre.id} « #{chapitre.title} ».",
            "Contenu : #{taille(contenu.to_s)}",
            apercu_texte(contenu.to_s)
          ].join("\n")
        end

        def resume_modification(page, chapitre, titre, contenu, position)
          lignes = ["MODIFIER #{ligne_page(page)}"]
          if titre && titre != page.title
            lignes << "Titre : « #{page.title} » → « #{titre} »"
            citee = ::Guide::Links.backlinks(page)
            if citee.any? && ::Guide::Links.key(titre) != ::Guide::Links.key(page.title)
              lignes << "Liens [[…]] mis à jour dans #{citee.size} autre(s) page(s) : #{citee.map { |other| "« #{other.title} »" }.join(', ')}"
            end
          end
          lignes << "Chapitre : « #{page.chapter.title} » → « #{chapitre.title} »" if chapitre != page.chapter
          lignes << "Position dans le chapitre : #{position}" if position
          if contenu && contenu != page.body
            lignes << "Contenu remplacé : #{taille(page.body)} → #{taille(contenu)} (#{difference(page.body, contenu)})"
            lignes << apercu_texte(contenu)
          elsif contenu
            lignes << "Contenu : identique, inchangé."
          end
          lignes.join("\n")
        end

        def taille(texte) = "#{texte.lines.size} ligne(s), #{texte.length} caractères"

        def difference(avant, apres)
          avant = avant.lines.map(&:rstrip)
          apres = apres.lines.map(&:rstrip)
          "#{(apres - avant).size} ligne(s) ajoutée(s) ou changée(s), #{(avant - apres).size} retirée(s)"
        end

        def apercu_texte(texte)
          extrait = texte.lines.first(12).join.rstrip
          extrait += "\n…" if texte.lines.size > 12
          "--- Début du contenu ---\n#{extrait.presence || '(vide)'}"
        end
      end
    end
  end
end
