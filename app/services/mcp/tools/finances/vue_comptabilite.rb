module Mcp
  module Tools
    module Finances
      # Comptabilité > Vue d'ensemble (AccountingController#index) : les
      # entités et leurs exercices ouverts, le rappel de comptage de caisse,
      # l'échéancier qui presse, les dettes ouvertes.
      class VueComptabilite < Base
        include Commun

        tool "vue_comptabilite",
             title: "Vue d'ensemble de la comptabilité",
             description: "La page d'accueil de la Comptabilité : entités et exercices ouverts, nombre de comptes et " \
                          "d'écritures, dernier comptage de caisse, échéances en retard ou à moins de 30 jours, dettes " \
                          "et litiges ouverts. Le solde et la projection de trésorerie : tresorerie.",
             schema: { properties: {} }

        def call(_arguments)
          ouverts = FiscalYear.opened.includes(:legal_entity).ordered.to_a
          comptage = CashCount.validated.ordered.first
          echeances = ComplianceDeadline.outstanding.where(due_on: ..(Date.current + 30)).ordered.includes(:compliance_obligation).to_a
          retard, bientot = echeances.partition(&:overdue?)
          dettes = Liability.open.includes(:legal_entity).to_a

          lignes = ["Comptabilité au #{Date.current}"]
          lignes += LegalEntity.ordered.map do |e|
            annees = ouverts.select { |y| y.legal_entity_id == e.id }.map(&:label)
            "#{e.name} (#{e.form_label}, TVA #{e.vat_regime_label.downcase})#{' · INACTIVE' unless e.active?} · " \
              "exercice(s) ouvert(s) : #{annees.presence&.join(', ') || 'aucun'}"
          end
          lignes << "#{GeneralAccount.actives.count} comptes actifs au plan · #{JournalEntry.count} écritures"
          lignes << if comptage
                      jours = (Date.current - comptage.counted_on).to_i
                      "Dernier comptage de caisse : le #{comptage.counted_on} (il y a #{jours} jour(s))#{' : à refaire (compter_caisse)' if jours > 7}"
                    else
                      "La caisse n'a jamais été comptée (compter_caisse)."
                    end
          lignes << "Échéances en retard : #{retard.size}#{retard.any? ? " · #{retard.map { |d| "#{d.display_title} (#{d.due_on})" }.join(', ')}" : ''}"
          lignes << "Échéances à 30 jours : #{bientot.size}#{bientot.any? ? " · #{bientot.map { |d| "#{d.display_title} (#{d.due_on})" }.join(', ')}" : ''}"
          lignes << "Dettes et litiges ouverts : #{dettes.size}#{" · reste #{euros(dettes.sum(&:remaining_cents))}" if dettes.any?}"
          lignes << "Trésorerie et projection : tresorerie. Échéancier : echeancier. Paramétrage : parametrage_compta."
          lignes.join("\n")
        end
      end
    end
  end
end
