module Mcp
  module Tools
    module Finances
      # La page Trésorerie (`Finance::Treasury`) et les compteurs qui disent si
      # la compta est à jour : la file « À affecter » et la file « À payer ».
      class Tresorerie < Base
        include Commun

        tool "tresorerie",
             title: "Trésorerie de la fondation",
             description: "Vue d'ensemble : solde de chaque compte (banque, caisse, Stripe) et sa date, ce qui doit " \
                          "rentrer (séjours avec un reste dû) et sortir (file « À payer », charges fixes) sur 90 jours, " \
                          "le point bas prévu, et les compteurs « À affecter » et « À payer ».",
             schema: { properties: {} }

        def call(_arguments)
          blocs = [comptes, files].compact
          blocs << projection if tresorerie&.accounts&.any?
          blocs.join("\n\n")
        end

        SANS_ANCRE = " — sans solde d'ouverture, chiffre à ne pas croire".freeze

        private

        def tresorerie = @tresorerie ||= ::Finance::Treasury.for_foundation

        def comptes
          return "Aucune entité « fondation » active : la trésorerie n'a rien à lire." if tresorerie.nil?

          lignes = tresorerie.accounts.map do |solde|
            "  #{solde.account.name} (#{solde.account.kind_label}) : #{euros(solde.balance_cents)} au #{solde.as_of || '—'}" \
              "#{SANS_ANCRE unless solde.anchored?}"
          end
          "Trésorerie de #{LegalEntity.find_by(form: 'foundation')&.name} : #{euros(tresorerie.balance_cents)} " \
            "(au plus tôt au #{tresorerie.as_of || '—'})\n#{lignes.join("\n")}"
        end

        def files
          en_attente = CashEntry.pending
          queue = ::Finance::PayableQueue.new
          a_payer = queue.rows.sum(&:remaining_cents)
          en_retard = queue.rows.count(&:payable_overdue?)
          factures = PurchaseInvoice.where(status: %w[to_process to_validate disputed]).group(:status).count
          notes = ExpenseReport.where(status: "recorded").count
          [
            "À affecter : #{en_attente.count} ligne(s), #{euros(en_attente.sum(:amount_cents))} net (lignes_tresorerie).",
            "À payer : #{queue.rows.size} dette(s), #{euros(a_payer)}#{", dont #{en_retard} en retard" if en_retard.positive?} (a_payer).",
            "Factures d'achat : #{factures['to_process'].to_i} à traiter, #{factures['to_validate'].to_i} à valider, " \
            "#{factures['disputed'].to_i} contestée(s). Notes de frais enregistrées à traiter : #{notes}."
          ].join("\n")
        end

        def projection
          bas = tresorerie.lowest_point
          retards = tresorerie.late_receivables
          [
            "Sur 90 jours (jusqu'au #{tresorerie.horizon_end}) : #{euros(tresorerie.incoming_cents)} attendus, " \
            "#{euros(tresorerie.outgoing_cents)} à sortir. Point bas : #{euros(bas.balance_cents)} le #{bas.date}.",
            ("Séjours partis avec un reste dû : #{retards.size} pour #{euros(retards.sum(&:amount_cents))} " \
             "(#{retards.first(5).map { |r| "séjour ##{r.stay.id} #{euros(r.amount_cents)}" }.join(', ')}" \
             "#{' …' if retards.size > 5})." if retards.any?)
          ].compact.join("\n")
        end
      end
    end
  end
end
