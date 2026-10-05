module Mcp
  module Tools
    module Finances
      # Comptabilité > À payer (PayablesController) : ce que la maison doit,
      # par échéance — factures d'achat, notes de frais, dépôts-ventes, parts
      # d'organisateurs, relevés de porteurs — plus les comptes de membres en
      # crédit (cuisiniers du batch cooking) à virer.
      class APayer < Base
        include Commun

        tool "a_payer",
             title: "À payer",
             description: "La file des dettes à payer, triée par échéance : bénéficiaire, montant restant, retard, " \
                          "communication à mettre sur le virement et IBAN connu ou non. Ajoute les échéances de " \
                          "l'échéancier sans facture encodée, et les comptes de membres en crédit à virer. " \
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

          membres = ::Finance::MemberPayables.new
          if membres.any?
            blocs << "Comptes de membres en crédit (#{euros(membres.total_cents)}) :\n" +
                     membres.rows.map { |r| "#{r.member_account.code} #{r.member_account.name} : #{euros(r.due_cents)} · #{r.payable? ? 'IBAN connu' : 'IBAN MANQUANT'}" }.join("\n")
          end
          blocs.join("\n\n")
        end
      end
    end
  end
end
