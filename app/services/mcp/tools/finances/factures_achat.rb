module Mcp
  module Tools
    module Finances
      # Comptabilité > Achats (PurchaseInvoicesController#index et #show) : la
      # file des factures fournisseurs, ou le détail d'une facture.
      class FacturesAchat < Base
        include Commun

        tool "factures_achat",
             title: "Factures d'achat",
             description: "Les factures fournisseurs et leur parcours : à traiter (lignes à ventiler) → à valider (un " \
                          "pôle doit dire oui) → à payer (écriture passée) → payée (rapprochée d'une sortie), ou " \
                          "contestée. Sans `facture` : la liste filtrée, avec les totaux par statut. Avec `facture` : " \
                          "le détail (lignes, paiements, validation, historique).",
             schema: {
               properties: {
                 facture: FACTURE,
                 statut: { type: "string", enum: PurchaseInvoice::STATUSES, description: "to_process, to_validate, to_pay, paid ou disputed." },
                 recherche: { type: "string", description: "Fournisseur, numéro ou communication." },
                 pole: POLE.merge(description: "Ne garder que les factures dont une ligne va à ce pôle."),
                 du: DATE, au: DATE
               }
             }

        LIMITE = 60

        def call(arguments)
          return fiche(facture!(arguments["facture"])) if arguments["facture"].present?

          scope = PurchaseInvoice.ordered.includes(:third_party, :legal_entity, :cash_allocations)
          scope = scope.with_status(arguments["statut"]) if arguments["statut"].present?
          if arguments["recherche"].present?
            motif = "%#{PurchaseInvoice.sanitize_sql_like(arguments['recherche'].to_s.strip)}%"
            scope = scope.left_joins(:third_party).where("third_parties.name ILIKE :m OR purchase_invoices.number ILIKE :m " \
                                                         "OR purchase_invoices.payment_reference ILIKE :m", m: motif)
          end
          if arguments["pole"].present?
            scope = scope.where(id: PurchaseInvoiceLine.where(team_id: pole!(arguments["pole"]).id).select(:purchase_invoice_id))
          end
          scope = scope.where(issued_on: date!(arguments["du"], "du")..) if arguments["du"].present?
          scope = scope.where(issued_on: ..date!(arguments["au"], "au")) if arguments["au"].present?

          totaux = PurchaseInvoice::STATUSES.map do |statut|
            base = PurchaseInvoice.with_status(statut)
            "#{PurchaseInvoice::STATUS_LABELS[statut]} #{base.count} (#{euros(base.sum(:total_cents))})"
          end
          factures = scope.limit(LIMITE + 1).to_a
          corps = factures.first(LIMITE).map { |f| ligne_facture(f) }
          corps << "… et d'autres : précise les filtres." if factures.size > LIMITE
          "Toutes les factures : #{totaux.join(' · ')}\n\n#{corps.presence&.join("\n") || 'Aucune facture ne correspond.'}"
        end

        private

        def fiche(facture)
          details = [ligne_facture(facture)]
          details << "Communication : #{facture.payment_reference}" if facture.payment_reference.present?
          details << "⚠ Double signature à la banque (#{euros(PurchaseInvoice::DOUBLE_SIGNATURE_CENTS)} ou plus)." if facture.double_signature?
          if facture.requires_validation?
            details << "Validation : pôle #{facture.validation_team&.name || '—'}" \
                       "#{facture.validated_at ? " — validée le #{I18n.l(facture.validated_at.to_date)} par #{facture.validated_by&.email}" : ' — pas encore validée'}"
          end
          details << "Contestée : #{facture.dispute_reason}" if facture.dispute_reason.present?
          details << "Défauts : #{facture.quality_flags.join(', ')} (no_document = pièce PDF à joindre dans Claudy)" if facture.quality_flags.present?
          details << "Notes : #{facture.notes}" if facture.notes.present?
          lignes = facture.purchase_invoice_lines.map do |l|
            "  #{euros(l.amount_cents)} → #{l.general_account}#{" · pôle #{l.team.name}" if l.team}#{" · « #{l.label} »" if l.label.present?}"
          end
          ecart = facture.total_cents - facture.lines_total_cents
          details << "Lignes#{" (reste #{euros(ecart)} à ventiler)" unless ecart.zero?} :\n#{lignes.presence&.join("\n") || '  aucune'}"
          paiements = facture.cash_allocations.includes(:cash_entry).map do |a|
            "  ligne de trésorerie ##{a.cash_entry_id} du #{a.cash_entry&.entry_date} : #{euros(a.amount_cents.abs)}"
          end
          details << "Paiements :\n#{paiements.join("\n")}" if paiements.any?
          details << "Écriture d'achat passée le #{I18n.l(facture.posted_at.to_date)}." if facture.posted?
          versions = facture.versions.reorder(created_at: :desc).limit(8).map do |v|
            "  #{I18n.l(v.created_at, format: '%d/%m/%Y %H:%M')} #{v.event} par #{v.whodunnit || '—'}"
          end
          details << "Historique :\n#{versions.join("\n")}" if versions.any?
          details.join("\n")
        end
      end
    end
  end
end
