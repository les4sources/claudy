module Mcp
  module Tools
    module Finances
      # Comptabilité > Notes de frais (ExpenseReportsController#index et
      # #show) : notes de frais (achats avancés par un membre) et notes de
      # mission (kilomètres).
      class NotesDeFrais < Base
        include Commun

        tool "notes_de_frais",
             title: "Notes de frais et de mission",
             description: "Les notes de frais et de mission des membres. Parcours : enregistrée (modifiable) → en " \
                          "traitement (écriture passée, à rembourser) → payée (rapprochée d'une sortie ou payée en " \
                          "caisse), ou rejetée avec un motif. Sans `note` : la liste filtrée ; avec `note` : le détail.",
             schema: {
               properties: {
                 note: NOTE,
                 statut: { type: "string", enum: ExpenseReport::STATUSES, description: "recorded, processing, paid ou rejected." },
                 type: { type: "string", enum: ExpenseReport::KINDS, description: "expenses (frais) ou mileage (mission)." },
                 membre: { type: "string", description: "Le membre qui a avancé l'argent (nom, ou « moi »)." },
                 du: DATE, au: DATE
               }
             }

        LIMITE = 60

        def call(arguments)
          return fiche(note!(arguments["note"])) if arguments["note"].present?

          scope = ExpenseReport.recent_first.includes(:human, :expense_lines, :cash_allocations)
          scope = scope.with_status(arguments["statut"]) if arguments["statut"].present?
          scope = scope.of_kind(arguments["type"]) if arguments["type"].present?
          scope = scope.for_human(membre!(arguments["membre"]).id) if arguments["membre"].present?
          scope = scope.where(submitted_on: date!(arguments["du"], "du")..) if arguments["du"].present?
          scope = scope.where(submitted_on: ..date!(arguments["au"], "au")) if arguments["au"].present?

          notes = scope.limit(LIMITE + 1).to_a
          return "Aucune note ne correspond." if notes.empty?

          corps = notes.first(LIMITE).map { |n| "#{ligne_note(n)} · #{n.submitted_on || '—'}" }
          corps << "… et d'autres : précise les filtres." if notes.size > LIMITE
          corps.join("\n")
        end

        private

        def fiche(note)
          details = ["#{ligne_note(note)} · #{note.legal_entity&.name} · déposée le #{note.submitted_on || '—'}"]
          details << "Passée en traitement le #{note.processed_on}." if note.processed_on
          details << "Payée le #{note.paid_on}." if note.paid_on
          details << "IBAN du membre : #{note.human&.iban.present? ? 'connu' : 'MANQUANT (le virement ne peut pas partir)'}" unless note.paid?
          details << "Notes : #{note.notes}" if note.notes.present?
          lignes = note.expense_lines.sort_by { |l| [l.spent_on, l.position, l.id] }.map do |l|
            km = l.distance_km ? " · #{format('%g', l.distance_km)} km" : ""
            "  #{l.spent_on} #{l.label}#{" (#{l.supplier_name})" if l.supplier_name.present?} : #{euros(l.amount_cents)}#{km} → " \
              "#{l.general_account}#{" · pôle #{l.team.name}" if l.team}#{' · sans justificatif' unless l.receipt.attached?}"
          end
          details << "Lignes :\n#{lignes.presence&.join("\n") || '  aucune'}"
          paiements = note.cash_allocations.includes(:cash_entry).map do |a|
            "  ligne de trésorerie ##{a.cash_entry_id} du #{a.cash_entry&.entry_date} : #{euros(a.amount_cents.abs)}"
          end
          details << "Paiements :\n#{paiements.join("\n")}" if paiements.any?
          details.join("\n")
        end
      end
    end
  end
end
