module Mcp
  module Tools
    module Finances
      # Une ligne de la file « À affecter », dépliée comme à l'écran : ses
      # affectations, la suggestion d'une règle (ou de Jev) et les pistes de
      # rapprochement — séjour, compte d'un habitant, facture, note de frais,
      # versement Stripe.
      #
      # Comme l'écran, l'ouvrir calcule la suggestion de la ligne si elle n'en
      # a pas : c'est une PROPOSITION, rangée à part, qui ne pèse sur aucun
      # solde tant que personne ne l'accepte.
      class FicheLigneTresorerie < Base
        include Commun

        tool "fiche_ligne_tresorerie",
             title: "Fiche d'une ligne de trésorerie",
             description: "Le détail d'une ligne de banque, de caisse ou de Stripe : contrepartie, IBAN, communication, " \
                          "affectations, comptabilisation, suggestion d'affectation, et les pistes de rapprochement " \
                          "(séjour à ventiler, règlement d'un habitant, facture d'achat, note de frais, virement à un " \
                          "membre, facture de vente, versement Stripe), avec les identifiants à passer à " \
                          "rapprocher_ligne, affecter_ligne ou geste_ligne_tresorerie.",
             schema: { properties: { ligne: LIGNE }, required: %w[ligne] }

        def call(arguments)
          entry = ligne!(arguments["ligne"])
          proposer(entry)
          entry = ligne!(entry.id)

          [identite(entry), affectations(entry), suggestion(entry), pistes(entry), commentaires(entry)].compact.join("\n\n")
        end

        private

        def proposer(entry)
          return unless entry.status == "pending" && entry.cash_allocations.empty?

          PaperTrail.request(whodunnit: "claude:#{user.email}") do
            ::Finance::SuggestAllocations.new(cash_entries: [entry], whodunnit: "claude:#{user.email}", jev: Jev::Client.new).run!
          end
        rescue StandardError => e
          Rails.logger.warn("[MCP] suggestion de la ligne ##{entry.id} : #{e.class} #{e.message}")
        end

        def identite(entry)
          details = [ligne_tresorerie(entry)]
          details << "Libellé : #{entry.label}"
          details << "Contrepartie : #{entry.counterparty_name}#{" · IBAN #{entry.counterparty_iban}" if entry.counterparty_iban.present?}" if entry.counterparty_name.present? || entry.counterparty_iban.present?
          details << "Communication : #{entry.communication}" if entry.communication.present?
          extra = []
          extra << "date valeur #{entry.value_date}" if entry.value_date
          extra << "code #{entry.transaction_code}" if entry.transaction_code.present?
          extra << "relevé #{entry.statement_ref}" if entry.statement_ref.present?
          extra << "motif de caisse « #{entry.cash_motif.label} »" if entry.cash_motif
          details << extra.join(" · ").upcase_first if extra.any?
          details << "Notes : #{entry.notes}" if entry.notes.present?
          details << "Comptabilisée : écriture #{entry.journal_entry&.id ? "##{entry.journal_entry.id}" : 'passée'}" if entry.posted?
          details.join("\n")
        end

        def affectations(entry)
          return nil if entry.cash_allocations.empty?

          "Affectations (#{euros(entry.allocated_cents)} sur #{euros(entry.amount_cents)}, reste #{euros(entry.remaining_cents)}) :\n" +
            entry.cash_allocations.sort_by(&:id).map { |a| "  #{ligne_affectation(a)}" }.join("\n")
        end

        def suggestion(entry)
          s = entry.allocation_suggestions.pending.ordered.first
          return nil if s.nil?

          "Suggestion ##{s.id} (#{s.source_label}, confiance #{s.confidence} %) : #{euros(s.amount_cents)} → #{s.general_account}" \
            "#{" · pôle #{s.team.name}" if s.team} · #{s.legal_entity&.name}#{" · événement #{s.event.name}" if s.event}\n" \
            "  Pourquoi : #{s.rationale}\n  → geste_ligne_tresorerie accepter_suggestion ou refuser_suggestion"
        end

        def pistes(entry)
          return nil if entry.cash_allocations.any? || entry.status == "excluded"

          pistes = entry.incoming? ? pistes_entree(entry) : pistes_sortie(entry)
          return "Aucune piste de rapprochement : affecte la ligne à un compte du plan (affecter_ligne)." if pistes.empty?

          "Pistes de rapprochement (rapprocher_ligne) :\n#{pistes.map { |p| "  #{p}" }.join("\n")}"
        end

        def pistes_entree(entry)
          pistes = []
          if (sejour = ::Finance::MatchStay.new(cash_entry: entry).run!)
            lignes = begin
              ::Finance::VentilateStay.new(stay: sejour.stay, amount_cents: entry.amount_cents).run!
            rescue ::Finance::VentilateStay::EmptyQuote, ::Finance::VentilateStay::MissingMapping => e
              e.message
            end
            ventilation = lignes.is_a?(String) ? "ventilation impossible : #{lignes}" : lignes.map { |l| "#{l.general_account&.code} #{euros(l.amount_cents)}" }.join(", ")
            pistes << "avec: sejour, sejour: #{sejour.stay.id} — #{sejour.stay.decorate.display_name} (confiance #{sejour.confidence} %, #{sejour.rationale}) · #{ventilation}"
          end
          ::Finance::MatchMemberSettlements.new.for_entry(entry).each do |m|
            pistes << "avec: reglement_membre, compte: #{m.member_account.code} — #{m.member_account.name} doit #{euros(m.due_cents)}, " \
                      "poste probable #{m.flow_label} (#{m.reason}, #{m.confidence} %)"
          end
          ::Finance::MatchSalesInvoices.new.for_entry(entry).each do |m|
            pistes << "avec: facture_vente, facture_vente: #{m.invoice.id} — #{m.invoice.label} #{euros(m.invoice.total_cents)} (#{m.reason})"
          end
          ::Finance::MatchStripePayouts.new.for_entry(entry).each do |m|
            pistes << "avec: versement_stripe, versement_stripe: #{m.payout.id} — #{m.payout.account_label} #{euros(m.payout.amount_cents)} " \
                      "arrivé le #{m.payout.arrival_date} (#{m.reason})"
          end
          pistes
        end

        def pistes_sortie(entry)
          pistes = []
          ::Finance::MatchPurchaseInvoices.new.for_entry(entry).each do |m|
            pistes << "avec: facture_achat, facture: #{m.invoice.id} — #{m.invoice.payable_label} reste #{euros(m.due_cents)} (#{m.reason})"
          end
          ::Finance::MatchExpenseReports.new.for_entry(entry).each do |m|
            pistes << "avec: note_de_frais, note: #{m.report.id} — #{m.report.payable_label} de #{m.beneficiary} reste #{euros(m.due_cents)} (#{m.reason})"
          end
          ::Finance::MatchMemberPayouts.new.for_entry(entry).each do |m|
            pistes << "avec: virement_membre, compte: #{m.member_account.code} — #{m.member_account.name} attend #{euros(m.due_cents)} (#{m.reason})"
          end
          pistes
        end

        def commentaires(entry)
          commentaires = entry.comments.order(:created_at).last(5)
          return nil if commentaires.empty?

          "Commentaires :\n" + commentaires.map { |c| "  #{I18n.l(c.created_at, format: '%d/%m %H:%M')} #{c.author&.email} : #{texte_commentaire(c)}" }.join("\n")
        end

        def texte_commentaire(comment)
          corps = comment.respond_to?(:body) ? comment.body : comment.try(:content)
          (corps.respond_to?(:to_plain_text) ? corps.to_plain_text : corps.to_s).squish.truncate(200)
        end
      end
    end
  end
end
