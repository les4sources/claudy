module Mcp
  module Tools
    module Finances
      # Comptabilité > À payer (PayablesController) : ce que la maison doit,
      # par échéance — factures d'achat, notes de frais, dépôts-ventes, parts
      # d'organisateurs, relevés de porteurs, partages de revenus et comptes de
      # membres en crédit (cuisiniers du batch cooking).
      class APayer < Base
        include Commun

        tool "a_payer",
             title: "À payer",
             description: "La file des dettes à payer, triée par échéance : bénéficiaire, montant restant, retard, " \
                          "communication à mettre sur le virement et IBAN connu ou non. Ajoute les échéances de " \
                          "l'échéancier sans facture encodée. Les partages de revenus émis et les comptes de membres en crédit " \
                          "(cuisiniers du batch cooking) sont dans la file. " \
                          "Ajoute aussi les dettes et litiges sans facture (taxe réclamée, arriéré, contestation). " \
                          "Le paiement lui-même se constate depuis la ligne bancaire (rapprocher_ligne).",
             schema: { properties: {} }

        def call(_arguments)
          queue = ::Finance::PayableQueue.new
          lignes = queue.rows.map do |dette|
            retard = dette.payable_overdue? ? " · EN RETARD de #{dette.payable_days_late} j" : ""
            "#{dette.payable_label} (#{dette.class.name} ##{dette.id}) · #{dette.payable_beneficiary} · reste #{euros(dette.remaining_cents)}" \
              "#{" sur #{euros(dette.payable_amount_cents)}" if dette.partially_paid?} · échéance #{dette.payable_due_on || '—'}#{retard} · " \
              "communication « #{dette.payable_communication} » · #{dette.payable_ready? ? 'IBAN connu' : 'IBAN MANQUANT'}"
          end
          blocs = ["À payer : #{queue.rows.size} dette(s), #{euros(queue.rows.sum(&:remaining_cents))}.\n#{lignes.join("\n")}".strip]

          attendus = queue.expected_payments.map do |echeance|
            "#{echeance.compliance_obligation&.title} (#{echeance.compliance_obligation&.legal_entity&.name}) · échéance #{echeance.due_on}"
          end
          blocs << "Échéances sans facture encodée :\n#{attendus.join("\n")}" if attendus.any?

          dettes = Liability.open.includes(:legal_entity, :third_party).ordered.to_a
          if dettes.any?
            blocs << "Dettes et litiges sans facture (#{euros(dettes.sum(&:remaining_cents))} retenus, " \
                     "comptés dans la trésorerie) :\n" + dettes.map { |d| ligne_dette(d) }.join("\n")
          end

          blocs.join("\n\n")
        end
      end
    end
  end
end
