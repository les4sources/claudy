module Mcp
  module Tools
    module Finances
      # Le journal de trésorerie et sa file « À affecter » (CashEntriesController
      # #index et #unallocated), avec les mêmes filtres.
      class LignesTresorerie < Base
        include Commun

        STATUTS = { "a_affecter" => "pending", "affectees" => "allocated", "exclues" => "excluded", "toutes" => nil }.freeze
        PAR_PAGE = 50

        tool "lignes_tresorerie",
             title: "Lignes de trésorerie",
             description: "Les mouvements de banque, de caisse et de Stripe. Par défaut la file « À affecter » (ce qui " \
                          "attend son affectation comptable), la plus récente d'abord. Filtres : statut, compte, période, " \
                          "recherche (nom, communication, libellé), sens, fourchette de montant (en valeur absolue). " \
                          "Pour le détail d'une ligne, ses suggestions et ses pistes de rapprochement : fiche_ligne_tresorerie.",
             schema: {
               properties: {
                 statut: { type: "string", enum: STATUTS.keys, description: "a_affecter (défaut), affectees, exclues ou toutes." },
                 compte: { type: "string", description: "Compte de trésorerie (nom : « Belfius », « Caisse », « Stripe »)." },
                 type_compte: { type: "string", enum: CashAccount::KINDS, description: "bank, cash ou stripe." },
                 du: DATE, au: DATE,
                 recherche: { type: "string" },
                 sens: { type: "string", enum: %w[entree sortie] },
                 min: MONTANT.merge(description: "Montant minimal (valeur absolue)."),
                 max: MONTANT.merge(description: "Montant maximal (valeur absolue)."),
                 page: { type: "integer", description: "Page (50 lignes par page)." }
               }
             }

        def call(arguments)
          statut = arguments["statut"].presence || "a_affecter"
          raise Error, "statut : #{STATUTS.keys.join(', ')}." unless STATUTS.key?(statut)

          scope = CashEntry.ordered.includes(:cash_account, :allocation_suggestions, :journal_entries,
                                             cash_allocations: :general_account)
          scope = scope.where(status: STATUTS[statut]) if STATUTS[statut]
          scope = scope.where(cash_account_id: compte_tresorerie!(arguments["compte"]).id) if arguments["compte"].present?
          scope = scope.where(cash_account_id: CashAccount.where(kind: arguments["type_compte"]).select(:id)) if arguments["type_compte"].present?
          scope = scope.where(entry_date: date!(arguments["du"], "du")..) if arguments["du"].present?
          scope = scope.where(entry_date: ..date!(arguments["au"], "au")) if arguments["au"].present?
          scope = scope.matching(arguments["recherche"]) if arguments["recherche"].present?
          scope = arguments["sens"] == "entree" ? scope.incoming : scope.outgoing if arguments["sens"].present?
          if arguments["min"].present? || arguments["max"].present?
            scope = scope.amount_between(arguments["min"].presence && cents!(arguments["min"], "min").abs,
                                         arguments["max"].presence && cents!(arguments["max"], "max").abs)
          end

          total = scope.count
          page = [arguments["page"].to_i, 1].max
          lignes = scope.offset((page - 1) * PAR_PAGE).limit(PAR_PAGE).to_a
          entete = "#{total} ligne(s) (#{statut.tr('_', ' ')})#{", page #{page}/#{(total / PAR_PAGE.to_f).ceil}" if total > PAR_PAGE}. " \
                   "File « À affecter » entière : #{CashEntry.pending.count} ligne(s)."
          return entete if lignes.empty?

          corps = lignes.map do |entry|
            texte = ligne_tresorerie(entry)
            suggestion = entry.allocation_suggestions.find { |s| s.status == "pending" }
            texte += "\n    suggestion : #{suggestion.general_account&.code} #{suggestion.general_account&.name} (#{suggestion.confidence} %)" if suggestion
            if entry.cash_allocations.any? && statut != "a_affecter"
              texte += "\n    #{entry.cash_allocations.map { |a| "#{a.general_account&.code} #{euros(a.amount_cents)}" }.join(', ')}"
            end
            texte
          end
          "#{entete}\n#{corps.join("\n")}"
        end
      end
    end
  end
end
