module Mcp
  module Tools
    module Finances
      # Comptabilité › États › Budget (Finance::BudgetsController#update) :
      # fixer ou corriger des lignes du budget détaillé, ou enregistrer le
      # brouillon tel quel. Un budget n'est pas une écriture : il ne touche pas
      # au grand livre, PaperTrail garde l'historique.
      class ModifierBudget < Ecriture
        include Commun

        tool "modifier_budget",
             title: "Modifier le budget détaillé",
             description: "Fixe le montant annuel de lignes du budget (entité × année × pôle × compte de classe 6 ou 7), " \
                          "toujours en positif. Un montant vide retire la ligne. `enregistrer_brouillon` enregistre d'abord " \
                          "toutes les propositions du brouillon (le réel de référence), puis applique `lignes`. Lire : budget.",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Défaut : la fondation."),
                 annee: { type: "integer", description: "Défaut : l'an prochain." },
                 enregistrer_brouillon: { type: "boolean", description: "Enregistrer les propositions du brouillon telles quelles." },
                 lignes: {
                   type: "array",
                   items: {
                     type: "object",
                     properties: {
                       pole: POLE.merge(description: "Pôle (nom), ou « aucun »."),
                       compte: COMPTE_GENERAL,
                       montant: { type: %w[number string null], description: "Montant annuel en euros, positif. Vide : retirer la ligne." }
                     },
                     required: %w[compte]
                   }
                 }
               }
             }

        private

        def planifier(arguments)
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : fondation!
          annee = (arguments["annee"].presence || Date.current.year + 1).to_i
          feuille = Finance::BudgetSheet.new(legal_entity: entite, year: annee)
          montants = {}
          if arguments["enregistrer_brouillon"]
            raise Error, "Le budget #{annee} de #{entite.name} n'est plus un brouillon." unless feuille.draft?

            feuille.rows.each { |row| montants[row.key] = cents_texte(row.budget_cents) }
          end
          Array(arguments["lignes"]).each { |ligne| montants.merge!(changement!(ligne)) }
          raise Error, "Rien à changer : donne `lignes` ou `enregistrer_brouillon`." if montants.empty?

          actuel = feuille.rows.index_by(&:key)
          resume = ["Budget #{annee} de #{entite.name} :",
                    *montants.map { |key, valeur| ligne_resume(key, valeur, actuel[key]) }]
          Plan.new(resume: resume.join("\n"), empreinte: [entite.id, annee, montants.sort],
                   donnees: { entite: entite.id, annee: annee, montants: montants })
        end

        def appliquer(plan)
          feuille = Finance::BudgetSheet.new(legal_entity: LegalEntity.find(plan.donnees[:entite]), year: plan.donnees[:annee])
          erreurs = feuille.save(plan.donnees[:montants])
          raise Error, erreurs.to_sentence if erreurs.any?

          t = feuille.budget
          "Budget #{plan.donnees[:annee]} enregistré : produits #{euros(t.revenue_cents)} · charges " \
            "#{euros(t.expense_cents)} · résultat #{euros(t.net_cents)}."
        end

        def fondation! = LegalEntity.actives.find_by(form: "foundation") || raise(Error, "Donne l'entité.")

        def changement!(ligne)
          pole = ligne["pole"].to_s.strip
          equipe = pole.empty? || pole.casecmp?("aucun") ? nil : pole!(pole)
          compte = compte_general!(ligne["compte"])
          raise Error, "#{compte.code} n'est pas un compte de charges ou de produits." unless BudgetLine::CLASSES.include?(compte.klass)

          brut = ligne["montant"].to_s.strip
          cents = brut.empty? ? nil : Liability.parse_euros(brut.delete("€"))
          raise Error, "Montant illisible « #{ligne['montant']} »." if cents.nil? && brut.present?
          raise Error, "Un budget s'écrit en positif : c'est le compte qui dit charge ou produit." if cents&.negative?

          { Finance::BudgetSheet.key_for(equipe&.id, compte.id) => cents_texte(cents) }
        end

        def cents_texte(cents) = cents.nil? ? "" : format("%.2f", cents / 100.0)

        def ligne_resume(key, valeur, row)
          team_id, account_id = key.split("-").map(&:to_i)
          compte = row&.account || GeneralAccount.find(account_id)
          pole = row ? (row.team&.name || "Sans pôle") : (team_id.zero? ? "Sans pôle" : Team.find(team_id).name)
          avant = row&.line ? euros(row.line.amount_cents) : "rien"
          apres = valeur.empty? ? "retirée" : euros(Liability.parse_euros(valeur))
          "  #{pole} · #{compte.code} #{compte.name} : #{avant} → #{apres}"
        end
      end
    end
  end
end
