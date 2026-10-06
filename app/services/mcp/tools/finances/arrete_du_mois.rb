module Mcp
  module Tools
    module Finances
      # Comptabilité > Arrêté du mois (MonthlyCloseController#show) : la liste
      # de contrôle qui dit si un mois peut être arrêté.
      class ArreteDuMois < Base
        include Commun

        SIGNES = { done: "✓", todo: "✗", warning: "⚠" }.freeze

        tool "arrete_du_mois",
             title: "Arrêté du mois",
             description: "La liste de contrôle d'un mois : relevés importés, tout affecté, charges récurrentes " \
                          "générées, décomptes émis et envoyés, règlements, Stripe, contrôles, arrêté. ✗ bloque " \
                          "l'arrêté, ⚠ avertit. Défaut : le mois précédent. Pour arrêter ou rouvrir : arreter_mois.",
             schema: { properties: { mois: MOIS } }

        def call(arguments)
          mois = mois!(arguments["mois"], defaut: Date.current.prev_month.beginning_of_month)
          etapes = ::Finance::MonthlyClose.call(month: mois)
          bloquantes = etapes.select(&:blocking?).reject { |e| e.key == :closing }
          lignes = etapes.map { |e| "#{SIGNES.fetch(e.status, '·')} #{e.title} — #{e.detail}" }
          derniers = MonthClosing.ordered.limit(4).map { |c| "#{c.label} (#{c.closed_by || '—'})" }

          [
            "#{nom_mois(mois).capitalize} : #{MonthClosing.closed?(mois) ? 'ARRÊTÉ' : "#{bloquantes.size} point(s) bloquant(s)"}",
            lignes.join("\n"),
            ("Derniers mois arrêtés : #{derniers.join(', ')}" if derniers.any?)
          ].compact.join("\n\n")
        end
      end
    end
  end
end
