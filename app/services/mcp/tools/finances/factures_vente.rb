module Mcp
  module Tools
    module Finances
      # Comptabilité > Clients > Ventes (SalesInvoicesController #index et
      # #show), et la file Facturation : ce qui attend sa facture.
      class FacturesVente < Base
        include Commun

        STATUTS = { "emises" => "issued", "payees" => "paid" }.freeze
        LIMITE = 60
        TYPES = { "stay" => "sejour", "booking" => "hebergement", "space_booking" => "espaces" }.freeze

        tool "factures_vente",
             title: "Factures de vente",
             description: "Le registre des factures émises (dans OkiOki) : numéro, date, client, montant, payée ou non, " \
                          "ce qu'elles facturent, avec le total facturé et le reste impayé du filtre. `a_facturer` : la " \
                          "file Facturation, les réservations dont la facture est demandée (type et #id à passer à " \
                          "facture_vente). Avec `facture` : le détail, dont les lignes bancaires qui l'ont payée.",
             schema: {
               properties: {
                 a_facturer: { type: "boolean", description: "Montrer la file « factures à fournir »." },
                 facture: { type: %w[integer string], description: "Une facture (#id ou numéro) pour en voir le détail." },
                 statut: { type: "string", enum: STATUTS.keys },
                 entite: ENTITE,
                 du: DATE, au: DATE,
                 recherche: { type: "string", description: "Numéro de facture." }
               }
             }

        def call(arguments)
          return detail(facture_vente!(arguments["facture"])) if arguments["facture"].present?
          return a_facturer if arguments["a_facturer"]

          scope = SalesInvoice.all
          if arguments["statut"].present?
            scope = scope.where(status: STATUTS[arguments["statut"]] || raise(Base::Error, "statut : #{STATUTS.keys.join(', ')}."))
          end
          scope = scope.where(legal_entity_id: entite!(arguments["entite"]).id) if arguments["entite"].present?
          scope = scope.where(issued_on: date!(arguments["du"], "du")..) if arguments["du"].present?
          scope = scope.where(issued_on: ..date!(arguments["au"], "au")) if arguments["au"].present?
          scope = scope.where("sales_invoices.number ILIKE ?", "%#{SalesInvoice.sanitize_sql_like(arguments['recherche'])}%") if arguments["recherche"].present?

          factures = scope.ordered.includes(:customer, :legal_entity, sales_invoice_sources: :source).limit(LIMITE).to_a
          entete = "Facturé #{euros(scope.sum(:total_cents))} · impayé #{euros(scope.issued.sum(:total_cents))} · " \
                   "#{Invoicing::Queue.new.requested.size} facture(s) à fournir (a_facturer)"
          return "#{entete}\nAucune facture." if factures.empty?

          "#{entete}\n#{factures.map { |f| ligne_vente(f) }.join("\n")}"
        end

        private

        def ligne_vente(f)
          "##{f.id} n° #{f.number} · #{f.issued_on} · #{f.customer_name || '—'} · #{euros(f.total_cents)} · " \
            "#{f.status_label.downcase} · #{f.legal_entity&.name}#{" · #{sources(f)}" if f.sales_invoice_sources.any?}" \
            "#{' · PDF' if f.document.attached?}"
        end

        def sources(f)
          f.sales_invoice_sources.map { |s| "#{TYPES[source_kind(s.source)] || s.source_type} ##{s.source_id}" }.join(", ")
        end

        def source_kind(source) = Invoicing::Queue::KINDS.key(source.class)

        def a_facturer
          lignes = Invoicing::Queue.new.requested
          return "Aucune facture à fournir." if lignes.empty?

          lignes.map do |l|
            "#{TYPES[l.kind]} ##{l.id} · #{l.label}#{" (#{l.sublabel})" if l.sublabel} · du #{l.from_date || '—'} au #{l.to_date || '—'} · " \
              "#{l.priceless? ? 'SANS MONTANT' : euros(l.price_cents)}"
          end.join("\n")
        end

        def detail(f)
          paiements = f.cash_allocations.includes(:cash_entry).map do |a|
            "  #{euros(a.amount_cents)} · ligne ##{a.cash_entry_id} du #{a.cash_entry&.entry_date} · #{a.cash_entry&.counterparty_name}"
          end
          [ligne_vente(f),
           ("Notes : #{f.notes}" if f.notes.present?),
           (paiements.any? ? "Payée par :\n#{paiements.join("\n")}" : "Aucun paiement rapproché (rapprocher_ligne facture_vente).")].compact.join("\n")
        end
      end
    end
  end
end
