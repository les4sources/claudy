module Mcp
  module Tools
    module Finances
      # Comptabilité > Plan comptable, Exercices et Paramètres > Entités juridiques
      # (GeneralAccountsController, LegalEntitiesController et
      # FiscalYearsController #index), désactivés compris.
      class ParametrageCompta < Base
        include Commun

        QUOI = %w[comptes entites exercices].freeze

        tool "parametrage_compta",
             title: "Plan comptable, entités, exercices",
             description: "Le paramétrage de la compta tel que l'écran le montre, désactivés compris : `comptes` (le " \
                          "plan, par classe ou recherche, avec nature, lettrable, long terme, actif), `entites` (forme, régime TVA, " \
                          "n° de TVA, exercices, comptes de trésorerie avec leur IBAN, écritures), `exercices` (dates, statut, " \
                          "écritures, par entité). Modifier : compte_general, entite_juridique, compte_tresorerie, exercice.",
             schema: {
               properties: {
                 quoi: { type: "string", enum: QUOI },
                 classe: { type: "integer", description: "Pour comptes : la classe (1 à 7)." },
                 recherche: { type: "string", description: "Pour comptes : code ou partie du nom." },
                 entite: ENTITE.merge(description: "Pour exercices : une seule entité.")
               },
               required: %w[quoi]
             }

        def call(arguments)
          case arguments["quoi"]
          when "comptes" then comptes(arguments)
          when "entites" then entites
          when "exercices" then exercices(arguments)
          else raise Error, "quoi : #{QUOI.join(', ')}."
          end
        end

        private

        def comptes(arguments)
          scope = GeneralAccount.ordered
          scope = scope.in_class(arguments["classe"].to_i) if arguments["classe"].present?
          if arguments["recherche"].present?
            motif = "%#{GeneralAccount.sanitize_sql_like(arguments['recherche'].to_s.strip)}%"
            scope = scope.where("code LIKE :m OR name ILIKE :m", m: motif)
          end
          comptes = scope.to_a
          return "Aucun compte." if comptes.empty?

          comptes.map do |c|
            "#{c} · classe #{c.klass} · #{c.nature_label.downcase}#{' · lettrable' if c.reconcilable}#{' · long terme' if c.long_term}#{' · DÉSACTIVÉ' unless c.active}"
          end.join("\n")
        end

        def entites
          ecritures = JournalEntry.group(:legal_entity_id).count
          LegalEntity.ordered.includes(:fiscal_years, cash_accounts: :general_account).map do |e|
            "##{e.id} #{e.name} · #{e.form_label} · TVA #{e.vat_regime_label.downcase}#{" n° #{e.vat_number}" if e.vat_number.present?}" \
              "#{' · INACTIVE' unless e.active?} · exercices #{e.fiscal_years.sort_by(&:starts_on).map { |y| "#{y.label}#{' (clôturé)' if y.closed?}" }.join(', ').presence || 'aucun'} · " \
              "#{e.cash_accounts.size} compte(s) de trésorerie · #{ecritures[e.id].to_i} écriture(s)" +
              e.cash_accounts.sort_by(&:name).map { |c| "\n  #{ligne_tresorerie(c)}" }.join
          end.join("\n").presence || "Aucune entité."
        end

        # L'IBAN est ce qui relie un relevé au compte : il se lit ici, il se
        # corrige avec compte_tresorerie.
        def ligne_tresorerie(c)
          "Compte de trésorerie ##{c.id} #{c.name} · #{c.kind_label} · IBAN #{c.iban.presence || 'aucun'} · " \
            "#{c.general_account}#{' · INACTIF' unless c.active?}"
        end

        def exercices(arguments)
          scope = FiscalYear.includes(:legal_entity).ordered
          scope = scope.where(legal_entity_id: entite_meme_inactive!(arguments["entite"]).id) if arguments["entite"].present?
          ecritures = JournalEntry.where(fiscal_year_id: scope.select(:id)).group(:fiscal_year_id).count
          scope.map { |y| "#{ligne_exercice(y)} · #{ecritures[y.id].to_i} écriture(s)" }.join("\n").presence || "Aucun exercice."
        end
      end
    end
  end
end
