module Mcp
  module Tools
    module Cuisine
      # Le reporting de la cuisine (Kitchen::ReportingController#show) : ce qui
      # a été facturé, par famille et par personne, et ce que disent les comptes.
      class BilanCuisine < Base
        include Commun

        tool "bilan_cuisine",
             title: "Bilan de la cuisine",
             description: "Le reporting de la cuisine sur une période : facturé (lignes facturables rattachées à un " \
                          "séjour), par famille et par responsable ; dépenses des comptes de charge de la cuisine et " \
                          "encaissé sur le compte de recette, lus en comptabilité. Défaut : l'année en cours.",
             schema: {
               properties: {
                 du: DATE.merge(description: "Début (défaut : 1er janvier)."),
                 au: DATE.merge(description: "Fin (défaut : 31 décembre)."),
                 detail: { type: "boolean", description: "Lister aussi chaque ligne facturée et chaque dépense." }
               }
             }

        def call(arguments)
          du = date_ou_nil(arguments["du"], "du") || Date.current.beginning_of_year
          au = date_ou_nil(arguments["au"], "au") || Date.current.end_of_year
          du, au = au, du if du > au
          recettes = Reports::KitchenRevenue.new(from: du, to: au)
          compta = Kitchen::AccountingReport.new(from: du, to: au)

          blocs = ["Cuisine du #{du} au #{au}", facture(recettes), comptes(compta)]
          blocs << detail(recettes, compta) if arguments["detail"]
          blocs.join("\n\n")
        end

        private

        def total(t) = "#{euros(t.price_cents)} (#{t.count} service(s), #{t.people} couverts)"

        def facture(recettes)
          lignes = ["Facturé : #{total(recettes.totals)}"]
          recettes.by_family.each { |famille, t| lignes << "- #{famille} : #{total(t)}" }
          lignes << "Par responsable :"
          recettes.by_responsible.each { |nom, t| lignes << "- #{nom} : #{total(t)}" }
          lignes.join("\n")
        end

        def comptes(compta)
          depenses = if compta.configured?
                       "Dépenses (#{compta.expense_accounts.map { |c| "#{c.code} #{c.name}" }.join(', ')}) : #{euros(compta.expenses_cents)}"
                     else
                       "Dépenses : aucun compte de charge désigné (modifier_reglages_cuisine)."
                     end
          encaisse = if compta.revenue_account?
                       "Encaissé sur #{compta.revenue_account.code} #{compta.revenue_account.name} : #{euros(compta.collected_cents)}"
                     else
                       "Encaissé : aucun compte de recette « repas » configuré en comptabilité."
                     end
          "#{depenses}\n#{encaisse}"
        end

        def detail(recettes, compta)
          lignes = recettes.lines.map { |order| "- #{ligne_prestation(order.object)}" }
          depenses = compta.expense_lines.map do |ligne|
            "- #{ligne.journal_entry.entry_date} #{ligne.general_account.code} #{ligne.label.presence || ligne.journal_entry.label} : #{euros(ligne.signed_cents)}"
          end
          "Lignes facturées :\n#{lignes.join("\n").presence || '(aucune)'}\n\nDépenses :\n#{depenses.join("\n").presence || '(aucune)'}"
        end
      end
    end
  end
end
