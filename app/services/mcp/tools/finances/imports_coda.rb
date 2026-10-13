module Mcp
  module Tools
    module Finances
      # Comptabilité > Banque & caisse > CODA (CodaImportsController#index et
      # #show) : les fichiers bancaires déposés, et le détail d'un dépôt.
      class ImportsCoda < Base
        include Commun

        LIMITE = 30

        tool "imports_coda",
             title: "Fichiers CODA déposés",
             description: "Les fichiers CODA (relevés bancaires) déjà déposés, du plus récent au plus ancien : date, " \
                          "fichier, relevés lus, lignes créées, statut. Avec `import` : le détail d'un dépôt (chaque " \
                          "relevé, son compte, ses soldes, ses lignes et le rapport de l'import). Pour déposer un " \
                          "nouveau fichier : importer_coda.",
             schema: {
               properties: {
                 import: { type: %w[integer string], description: "Un dépôt (#id) pour en voir le détail." }
               }
             }

        def call(arguments)
          return detail(id!(arguments["import"], "dépôt")) if arguments["import"].present?

          imports = CodaImport.ordered.limit(LIMITE).to_a
          return "Aucun fichier CODA déposé." if imports.empty?

          comptes = CashAccount.actives.where(kind: "bank").ordered.map do |compte|
            dernier = CodaStatement.last_for(compte)
            "#{compte.name}#{" (#{compte.iban})" if compte.iban.present?} : " \
              "#{dernier ? "dernier relevé #{dernier.label} au #{dernier.new_balance_date || '—'}, solde #{euros(dernier.new_balance_cents)}" : 'aucun relevé importé'}"
          end
          [
            "Comptes bancaires :\n#{comptes.map { |l| "  #{l}" }.join("\n")}",
            "Dépôts (les #{imports.size} plus récents) :\n#{imports.map { |i| "  #{ligne_import(i)}" }.join("\n")}"
          ].join("\n\n")
        end

        private

        def ligne_import(import)
          "##{import.id}  #{I18n.l(import.created_at.to_date)}  #{import.filename} · #{import.status_label.downcase} · " \
            "#{import.statements_count} relevé(s), #{import.entries_count} ligne(s) créée(s)" \
            "#{" · déposé par #{import.whodunnit}" if import.whodunnit.present?}"
        end

        def detail(id)
          import = CodaImport.find_by(id: id) || raise(Base::Error, "Aucun dépôt CODA ##{id}.")
          releves = import.coda_statements.includes(:cash_account).ordered.map do |r|
            "  Relevé #{r.label} · #{r.cash_account&.name} · du #{r.old_balance_date || '—'} (#{euros(r.old_balance_cents)}) " \
              "au #{r.new_balance_date || '—'} (#{euros(r.new_balance_cents)}) · #{r.entries_count} ligne(s)"
          end
          [
            ligne_import(import),
            ("Fichier créé par la banque le #{import.creation_date}" if import.creation_date),
            (releves.any? ? "Relevés :\n#{releves.join("\n")}" : "Aucun relevé."),
            ("Rapport :\n#{import.report}" if import.report.present?)
          ].compact.join("\n")
        end
      end
    end
  end
end
