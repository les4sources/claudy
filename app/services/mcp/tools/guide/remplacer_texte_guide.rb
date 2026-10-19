module Mcp
  module Tools
    module Guide
      # Corriger quelques mots d'une page du Guide sans renvoyer toute la page.
      class RemplacerTexteGuide < Ecriture
        include Commun

        tool "remplacer_texte_guide",
             title: "Corriger un passage d'une page du Guide",
             description: "Remplace un passage exact du Markdown d'une page (copie-le tel quel depuis page_guide) par " \
                          "un nouveau texte — une adresse, un numéro, une étape. Le passage doit être unique dans la " \
                          "page, sauf avec `partout`. Nouveau texte vide : le passage est supprimé. Devient une " \
                          "version de la page, signée de ton compte.",
             schema: {
               properties: {
                 page: PAGE,
                 ancien: { type: "string", description: "Le passage à remplacer, exactement comme dans le Markdown." },
                 nouveau: { type: "string", description: "Le texte qui le remplace (Markdown)." },
                 partout: { type: "boolean", description: "Remplacer toutes les occurrences." }
               },
               required: %w[page ancien nouveau]
             }

        private

        def planifier(arguments)
          page = page!(arguments["page"])
          ancien = arguments["ancien"].to_s
          nouveau = arguments["nouveau"].to_s
          raise Error, "Donne le passage à remplacer." if ancien.strip.empty?

          occurrences = page.body.scan(ancien).size
          raise Error, "Ce passage n'est pas dans la page ##{page.id} (copie-le exactement depuis page_guide)." if occurrences.zero?
          if occurrences > 1 && !arguments["partout"]
            raise Error, "Ce passage revient #{occurrences} fois dans la page : allonge-le pour qu'il soit unique, ou passe partout: true."
          end

          contenu = arguments["partout"] ? page.body.gsub(ancien, nouveau) : page.body.sub(ancien, nouveau)
          resume = "MODIFIER #{ligne_page(page)}\n#{occurrences > 1 ? "#{occurrences} occurrences" : 'Passage'} :\n" \
                   "- avant : « #{ancien.strip.truncate(400)} »\n- après : « #{nouveau.strip.truncate(400).presence || '(supprimé)'} »"
          Plan.new(resume: resume,
                   empreinte: [page.id, Digest::SHA256.hexdigest(page.body), Digest::SHA256.hexdigest(contenu)],
                   donnees: { page: page.id, contenu: contenu })
        end

        def appliquer(plan)
          page = GuidePage.find(plan.donnees[:page])
          ::Guide::SavePage.new(page, user: user, source: "mcp").call(body: plan.donnees[:contenu], summary: @motif)
          "#{ligne_page(page.reload)} — #{page.revisions.size} version(s)\nAdresse : #{lien_page(page)}"
        end
      end
    end
  end
end
