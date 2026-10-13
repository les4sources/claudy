module Mcp
  module Tools
    module Finances
      # Comptabilité > États > Contrôle croisé (CrossCheckController#index) :
      # le chiffre d'affaires du journal face aux séjours partis dans le mois et
      # à ce que Stripe a encaissé.
      class ControleCroise < Base
        include Commun

        tool "controle_croise",
             title: "Contrôle croisé du mois",
             description: "Pour un mois : les produits comptabilisés (classe 7) par pôle, le total des séjours partis " \
                          "dans le mois, les paiements en ligne encaissés, l'écart entre séjours et journal, et les " \
                          "lignes de trésorerie encore à affecter qui l'expliquent souvent.",
             schema: { properties: { mois: MOIS.merge(description: "Mois, AAAA-MM. Défaut : le mois en cours.") } }

        def call(arguments)
          mois = mois!(arguments["mois"], defaut: Date.current.beginning_of_month)
          du = mois.beginning_of_month
          au = mois.end_of_month

          produits = JournalLine.joins(:journal_entry, :general_account)
                                .where(journal_entries: { entry_date: du..au }, general_accounts: { klass: 7 })
                                .group(:team_id).pluck(Arel.sql("team_id, SUM(credit_cents) - SUM(debit_cents)"))
          poles = Team.where(id: produits.map(&:first).compact).index_by(&:id)
          journal = produits.sum { |_, montant| montant.to_i }
          sejours = Stay.where(departure_date: du..au)
          sejours_cents = sejours.sum(:total_amount_cents)
          encaisse = Payment.where(created_at: du.beginning_of_day..au.end_of_day, status: "paid").sum(:amount_cents)
          attente = CashEntry.pending.in_period(du, au)

          ["Contrôle croisé de #{nom_mois(mois)}",
           "Produits au journal : #{euros(journal)}",
           *produits.sort_by { |id, _| poles[id]&.name || "zzz" }.map { |id, m| "  #{id ? poles[id]&.name : 'non ventilé'} · #{euros(m.to_i)}" },
           "Séjours partis dans le mois : #{sejours.count} · #{euros(sejours_cents)}",
           "Paiements en ligne encaissés : #{euros(encaisse)}",
           "Écart séjours − journal : #{euros(sejours_cents - journal)}",
           "Lignes à affecter sur le mois : #{attente.count} · #{euros(attente.sum(:amount_cents))} " \
           "(#{CashEntry.pending.count} au total)"].join("\n")
        end
      end
    end
  end
end
