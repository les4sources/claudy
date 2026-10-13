module Mcp
  module Tools
    module Finances
      # Comptabilité > Trésorerie > Règles d'affectation (AllocationRulesController
      # #index), plus ce qui attend une décision : les suggestions en attente,
      # par règle et, pour Jev, par compte proposé — les lots qu'accepter_suggestions
      # peut accepter d'un coup.
      class ReglesAffectation < Base
        include Commun

        SEUILS = [95, 90, 80].freeze

        tool "regles_affectation",
             title: "Règles d'affectation et suggestions en attente",
             description: "Les règles d'affectation, dans leur ordre (la première qui reconnaît une ligne gagne) : " \
                          "critères, compte proposé, confiance, acceptations et refus, suggestions en attente. " \
                          "Puis les propositions de Jev en attente, par compte. Et le nombre de lignes « À affecter » " \
                          "sans aucune proposition. Pour créer ou corriger une règle : enregistrer_regle_affectation ; " \
                          "pour accepter un lot : accepter_suggestions.",
             schema: { properties: {} }

        def call(_arguments)
          regles = AllocationRule.ordered.includes(:general_account, :team, :legal_entity, :cash_account,
                                                   :analytic_account, :event).to_a
          en_attente = AllocationSuggestion.pending.joins(:cash_entry).where(cash_entries: { status: "pending" })

          parties = [bloc_regles(regles, en_attente), bloc_jev(en_attente), bloc_sans_proposition(en_attente)]
          parties.join("\n\n")
        end

        private

        def bloc_regles(regles, en_attente)
          return "Aucune règle d'affectation." if regles.empty?

          par_regle = en_attente.where.not(allocation_rule_id: nil).group(:allocation_rule_id)
                                .pluck(:allocation_rule_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(ABS(allocation_suggestions.amount_cents))"))
                                .to_h { |id, nombre, total| [id, [nombre, total]] }
          lignes = regles.map do |regle|
            nombre, total = par_regle[regle.id]
            attente = nombre ? "\n    #{nombre} suggestion(s) en attente, #{euros(total)}" : ""
            "#{ligne_regle(regle)}#{attente}"
          end
          "#{regles.size} règle(s) :\n#{lignes.join("\n")}"
        end

        def bloc_jev(en_attente)
          jev = en_attente.where(source: "jev").includes(:general_account).to_a
          return "Aucune proposition de Jev en attente." if jev.empty?

          lignes = jev.group_by(&:general_account).sort_by { |_compte, liste| -liste.size }.map do |compte, liste|
            seuils = SEUILS.map { |seuil| "#{liste.count { |s| s.confidence >= seuil }} à #{seuil} %+" }.join(", ")
            "  #{compte} : #{liste.size} (#{seuils}), #{euros(liste.sum { |s| s.amount_cents.abs })}"
          end
          "Propositions de Jev en attente, par compte (#{jev.size}) :\n#{lignes.join("\n")}"
        end

        def bloc_sans_proposition(en_attente)
          sans = CashEntry.pending.where.not(id: en_attente.select(:cash_entry_id))
          "Lignes « À affecter » sans aucune proposition : #{sans.count} (sur #{CashEntry.pending.count}). " \
            "Jev ne propose qu'à l'ouverture d'une ligne ; une règle propose dès son enregistrement."
        end
      end
    end
  end
end
