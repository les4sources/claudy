module Mcp
  module Tools
    module Finances
      # Les listes des formulaires de la compta : plan comptable, pôles,
      # entités, analytique, comptes de trésorerie, motifs de caisse, tiers,
      # événements. Ce qu'il faut pour remplir affecter_ligne ou une facture.
      class ReferentielComptable < Base
        include Commun

        QUOI = %w[comptes poles entites analytique tresorerie motifs_caisse tiers evenements].freeze

        tool "referentiel_comptable",
             title: "Référentiel comptable",
             description: "Les valeurs acceptées par les outils de la compta : comptes du plan (comptes, filtrables par " \
                          "classe ou recherche), pôles, entités juridiques, comptes analytiques, comptes de trésorerie, " \
                          "motifs de la feuille de caisse, tiers (fournisseurs, clients) et événements récents.",
             schema: {
               properties: {
                 quoi: { type: "string", enum: QUOI },
                 recherche: { type: "string", description: "Mot à chercher dans le code ou le nom." },
                 classe: { type: "integer", description: "Pour comptes : la classe du plan (6 = charges, 7 = produits…)." }
               },
               required: %w[quoi]
             }

        LIMITE = 80

        def call(arguments)
          quoi = arguments["quoi"].to_s
          raise Error, "quoi : #{QUOI.join(', ')}." unless QUOI.include?(quoi)

          @recherche = arguments["recherche"].to_s.strip.presence
          lignes = send(quoi, arguments)
          return "Rien ne correspond." if lignes.empty?

          "#{lignes.first(LIMITE).join("\n")}#{"\n… #{lignes.size - LIMITE} de plus : précise la recherche." if lignes.size > LIMITE}"
        end

        private

        def filtre(scope, *colonnes)
          return scope unless @recherche

          motif = "%#{scope.sanitize_sql_like(@recherche)}%"
          scope.where(colonnes.map { |c| "#{scope.table_name}.#{c} ILIKE :m" }.join(" OR "), m: motif)
        end

        def comptes(arguments)
          scope = filtre(GeneralAccount.actives.ordered, :code, :name)
          scope = scope.in_class(arguments["classe"].to_i) if arguments["classe"].present?
          scope.map { |a| "#{a.code} #{a.name} (#{a.nature_label})" }
        end

        def poles(_) = filtre(Team.order(:name), :name).map { |t| "#{t.name} (##{t.id})" }
        def entites(_) = filtre(LegalEntity.actives.ordered, :name).map { |e| "#{e.name} (#{e.form_label}, TVA #{e.vat_regime_label.to_s.downcase})" }

        def analytique(_)
          filtre(AnalyticAccount.actives.ordered.includes(:team), :code, :name).map { |a| "#{a}#{" · pôle #{a.team.name}" if a.team}" }
        end

        def tresorerie(_)
          filtre(CashAccount.actives.ordered.includes(:legal_entity), :name).map do |c|
            "#{c.name} (#{c.kind_label}) · #{c.legal_entity&.name}#{" · IBAN …#{c.iban.to_s.delete(' ').last(4)}" if c.iban.present?}"
          end
        end

        def motifs_caisse(_)
          filtre(CashMotif.actives.ordered.includes(:general_account, :team), :label).map do |m|
            "#{m.label} (##{m.id}, #{m.direction_label.to_s.downcase}) → #{m.general_account}#{" · pôle #{m.team.name}" if m.team}"
          end
        end

        def tiers(_)
          filtre(ThirdParty.actives.ordered, :name, :code).map do |t|
            "#{t.name} (#{t.code}, #{t.kind_label.to_s.downcase})#{" · TVA #{t.vat_number}" if t.vat_number.present?}"
          end
        end

        def evenements(_)
          filtre(Event.where("starts_at >= ?", 18.months.ago).order(starts_at: :desc), :name).map do |e|
            "Événement ##{e.id} #{e.name} · #{e.starts_at&.to_date}"
          end
        end
      end
    end
  end
end
