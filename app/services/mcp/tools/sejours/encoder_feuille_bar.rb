module Mcp
  module Tools
    module Sejours
      # La feuille de bar d'un groupe, recopiée sur son séjour (Michael,
      # 2026-10-13) — le geste de l'écran « Feuille de bar »
      # (StayBarSheetsController#update), par le même service.
      #
      # Claude lit la photo de la feuille ; c'est l'humain qui valide l'aperçu.
      # Un nom qu'on ne rapporte pas à un seul article arrête tout : on ne
      # facture pas au hasard.
      class EncoderFeuilleBar < Ecriture
        include Commun

        tool "encoder_feuille_bar",
             title: "Encoder la feuille de bar d'un séjour",
             description: "Ajoute au séjour les consommations notées sur la feuille de bar du groupe, au prix public du " \
                          "catalogue à la date du séjour ; elles s'ajoutent à son total, donc à sa facture. Chaque ligne : " \
                          "un article (#id rendu par articles_bar, ou son nom exact) et une quantité. « ajouter » (défaut) " \
                          "additionne aux quantités déjà encodées (seconde feuille) ; « remplacer » fait de cette feuille " \
                          "TOUT le bar du séjour (une quantité 0 retire l'article). Aucun email. Une ligne illisible sur la " \
                          "photo : demande à l'utilisateur plutôt que de deviner. La photo elle-même se joint dans Claudy, " \
                          "écran « Feuille de bar » du séjour.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 lignes: {
                   type: "array",
                   minItems: 1,
                   items: {
                     type: "object",
                     additionalProperties: false,
                     properties: {
                       article: { type: %w[integer string], description: "#id de l'article (articles_bar) ou son nom exact." },
                       quantite: { type: "integer", minimum: 0 }
                     },
                     required: %w[article quantite]
                   }
                 },
                 mode: { type: "string", enum: %w[ajouter remplacer], description: "ajouter (défaut) ou remplacer." }
               },
               required: %w[sejour lignes]
             }

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          remplacer = arguments["mode"] == "remplacer"
          quantites = quantites!(Array(arguments["lignes"]))
          # « remplacer » : un article encodé que la feuille ne cite pas sort.
          stay.bar_consumptions.each { |l| quantites[l.catalog_item_id] ||= 0 } if remplacer

          mode = remplacer ? "set" : "add"
          avant = stay.bar_consumptions.to_h { |l| [l.catalog_item_id, l.quantity] }
          resultat = simuler do
            copie = Stay.find(stay.id)
            rapport = Stays::EncodeBarSheet.new(stay: copie, quantities: quantites, mode: mode).run!
            [rapport, copie.bar_consumptions.ordered.map { |l| [l.catalog_item_id, l.label, l.quantity, l.unit_price_cents, l.price_cents] },
             copie.reload.total_amount_cents]
          end
          rapport, lignes_apres, total_apres = resultat
          raise Error, "Sans prix au catalogue à la date du séjour : #{rapport.unpriced.join(', ')}. Complète le catalogue d'abord." if rapport.unpriced.any?
          raise Error, "La feuille ne change rien au bar de ce séjour." if rapport.touched.zero?

          Plan.new(
            resume: resume(stay, avant, lignes_apres, total_apres, remplacer),
            empreinte: [etat(stay), avant.sort, quantites.sort, mode],
            donnees: { stay_id: stay.id, quantites: quantites, mode: mode }
          )
        end

        def appliquer(plan)
          d = plan.donnees
          stay = Stay.find(d[:stay_id])
          rapport = Stays::EncodeBarSheet.new(stay: stay, quantities: d[:quantites], mode: d[:mode]).run!
          "#{rapport.summary} Bar du séjour ##{stay.id} : #{euros(stay.bar_amount_cents)}. " \
            "Total du séjour : #{euros(stay.reload.total_amount_cents)}. " \
            "Pense à joindre la photo de la feuille sur l'écran « Feuille de bar » du séjour."
        end

        # { catalog_item_id => quantité }. Une même ligne citée deux fois sur la
        # feuille s'additionne.
        def quantites!(lignes)
          raise Error, "Donne au moins une ligne (article et quantité)." if lignes.empty?

          articles = BarConsumption.catalog_items.to_a
          inconnus = []
          quantites = {}
          lignes.each do |ligne|
            quantite = Integer(ligne["quantite"], exception: false)
            raise Error, "Quantité illisible pour « #{ligne['article']} »." if quantite.nil? || quantite.negative?

            article = trouver_article(articles, ligne["article"])
            if article
              quantites[article.id] = quantites.fetch(article.id, 0) + quantite
            else
              inconnus << ligne["article"].to_s
            end
          end
          raise Error, inconnus_message(inconnus, articles) if inconnus.any?

          quantites
        end

        def trouver_article(articles, reference)
          texte = reference.to_s.strip
          return articles.find { |a| a.id == texte.delete("#").to_i } if texte.delete("#").match?(/\A\d+\z/)

          exacts = articles.select { |a| a.name.casecmp?(texte) }
          exacts.size == 1 ? exacts.first : nil
        end

        def inconnus_message(inconnus, articles)
          details = inconnus.map do |nom|
            proches = articles.select { |a| a.active && a.name.downcase.include?(nom.downcase.first(4)) }.first(5)
            pistes = proches.any? ? " (pistes : #{proches.map { |a| "##{a.id} #{a.name}" }.join(', ')})" : ""
            "« #{nom} »#{pistes}"
          end
          "Article du bar introuvable : #{details.join(' ; ')}. Rapporte chaque ligne à un #id d'articles_bar, " \
            "ou demande à l'utilisateur ce que le groupe a voulu noter."
        end

        def resume(stay, avant, lignes_apres, total_apres, remplacer)
          bar_apres = lignes_apres.sum(&:last)
          details = lignes_apres.map do |id, label, quantite, unitaire, montant|
            ancien = avant[id]
            delta = ancien.nil? ? " (nouveau)" : (ancien == quantite ? "" : " (avant : #{ancien})")
            "- #{quantite} × #{label} à #{euros(unitaire)} = #{euros(montant)}#{delta}"
          end
          retires = avant.keys - lignes_apres.map(&:first)
          details += retires.map { |id| "- #{CatalogItem.find_by(id: id)&.name || "article ##{id}"} : retiré" }

          "#{ligne_sejour(stay)}\nFeuille de bar #{remplacer ? 'remplaçant tout le bar du séjour' : 'ajoutée'} :\n" \
            "#{details.join("\n")}\n" \
            "Bar : #{euros(stay.bar_amount_cents)} → #{euros(bar_apres)}\n" \
            "Total du séjour : #{euros(stay.total_amount_cents)} → #{euros(total_apres)}\nAucun email au client."
        end
      end
    end
  end
end
