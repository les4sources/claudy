module Mcp
  module Tools
    module Finances
      # Comptabilité > Fournisseurs > Charges fixes (RecurringExpensesController
      # #index) : ce que la maison paie à intervalle régulier, que la trésorerie
      # projette.
      class ChargesFixes < Base
        include Commun

        tool "charges_fixes",
             title: "Charges fixes",
             description: "Les charges qui reviennent (Voo, assurance, emprunt…) : #id, montant, fréquence, prochaine " \
                          "échéance, fournisseur, compte, entité, coût sur un an, et le total annuel des actives. Ce sont " \
                          "des prévisions de trésorerie, pas des dettes. Créer, corriger, supprimer : charge_fixe.",
             schema: { properties: {} }

        def call(_arguments)
          charges = RecurringExpense.ordered.includes(:third_party, :legal_entity, :general_account).to_a
          return "Aucune charge fixe." if charges.empty?

          annuel = charges.select(&:active?).sum(&:yearly_cents)
          ["Total annuel des charges actives : #{euros(annuel)}", *charges.map { |c| ligne_charge(c) }].join("\n")
        end

        private

        def ligne_charge(c)
          prochaine = c.active? ? c.next_due_on : nil
          ["##{c.id} #{c.label} · #{euros(c.amount_cents)} #{c.frequency_label.downcase}",
           ("prochaine échéance #{prochaine}" if prochaine),
           ("jusqu'au #{c.ends_on}" if c.ends_on),
           ("fournisseur #{c.third_party.name}" if c.third_party),
           ("compte #{c.general_account}" if c.general_account),
           c.legal_entity&.name,
           "#{euros(c.yearly_cents)} par an",
           ("INACTIVE" unless c.active?)].compact.join(" · ")
        end
      end
    end
  end
end
