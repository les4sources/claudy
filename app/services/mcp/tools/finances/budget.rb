module Mcp
  module Tools
    module Finances
      # Comptabilité › États › Budget (Finance::BudgetsController#show) : le
      # budget détaillé d'une entité pour une année, pôle par pôle et compte
      # par compte, face au réel de référence.
      class Budget < Base
        include Commun

        tool "budget",
             title: "Budget détaillé",
             description: "Le budget d'une entité pour une année : produits, charges et résultat prévus, puis une ligne " \
                          "par pôle et par compte (classes 6 et 7) avec le réel de référence (les 12 derniers mois " \
                          "complets pour l'an prochain, l'année d'avant sinon). Sans ligne enregistrée, c'est un " \
                          "brouillon qui propose ce réel. Modifier : modifier_budget.",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Défaut : la fondation."),
                 annee: { type: "integer", description: "Défaut : l'an prochain." },
                 pole: POLE.merge(description: "Ne montrer qu'un pôle (nom), ou « aucun » pour les lignes sans pôle.")
               }
             }

        def call(arguments)
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : fondation!
          annee = (arguments["annee"].presence || Date.current.year + 1).to_i
          feuille = Finance::BudgetSheet.new(legal_entity: entite, year: annee)
          groupes = filtrer(feuille.groups, arguments["pole"])

          entete = ["Budget #{annee} de #{entite.name}#{' (BROUILLON : rien d’enregistré, chaque ligne propose le réel)' if feuille.draft?}",
                    "Référence : #{feuille.reference_label}.",
                    totaux("Prévu", feuille.budget), totaux("Référence", feuille.reference)]
          if feuille.pending_count.positive?
            entete << "#{feuille.pending_count} ligne(s) de trésorerie à affecter (#{euros(feuille.pending_cents)} nets) : hors du réel."
          end
          return [*entete, "Aucune ligne."].join("\n") if groupes.empty?

          [*entete, *groupes.flat_map { |groupe| bloc(groupe) }].join("\n")
        end

        private

        def fondation! = LegalEntity.actives.find_by(form: "foundation") || raise(Error, "Donne l'entité.")

        def filtrer(groupes, pole)
          return groupes if pole.blank?
          return groupes.select { |groupe| groupe.team.nil? } if pole.to_s.strip.casecmp?("aucun")

          equipe = pole!(pole)
          groupes.select { |groupe| groupe.team == equipe }
        end

        def totaux(titre, t)
          "#{titre} : produits #{euros(t.revenue_cents)} · charges #{euros(t.expense_cents)} · résultat #{euros(t.net_cents)}"
        end

        def bloc(groupe)
          ["", "#{groupe.name} — #{totaux('prévu', groupe.budget)}",
           *groupe.rows.map do |row|
             prevu = row.budget_cents.nil? ? "rien de prévu" : "prévu #{euros(row.budget_cents)}"
             "  #{row.account.code} #{row.account.name} (#{row.expense? ? 'charge' : 'produit'}) : réel #{euros(row.reference_cents)} · #{prevu}"
           end]
        end
      end
    end
  end
end
