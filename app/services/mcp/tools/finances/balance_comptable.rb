module Mcp
  module Tools
    module Finances
      # Comptabilité > États > Balance (TrialBalanceController#index),
      # Balance tiers (ThirdPartyBalanceController#index) et Analytique
      # (AnalyticBalanceController#index).
      class BalanceComptable < Base
        include Commun

        tool "balance_comptable",
             title: "Balance générale ou analytique",
             description: "`generale` (défaut) : chaque compte mouvementé sur la période, total débit, total crédit et " \
                          "solde, et si la balance est équilibrée. `analytique` : par pôle, charges (classe 6), " \
                          "produits (classe 7) et résultat, plus ce qui n'est ventilé sur aucun pôle. `tiers` : au soir de " \
                          "`au` (défaut aujourd'hui), le solde de chaque fournisseur (comptes 44, `cote` " \
                          "fournisseurs) ou client (comptes 40, `cote` clients), plus gros d'abord. Défaut : " \
                          "l'année civile, toutes entités.",
             schema: {
               properties: {
                 vue: { type: "string", enum: %w[generale analytique tiers] },
                 cote: { type: "string", enum: %w[fournisseurs clients], description: "Pour la vue `tiers` (défaut fournisseurs)." },
                 entite: ENTITE.merge(description: "Facultatif : une seule entité."),
                 du: DATE, au: DATE,
                 classe: { type: "integer", description: "Pour la balance générale : une seule classe du plan (1 à 7)." }
               }
             }

        def call(arguments)
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : nil
          return tiers(entite, arguments) if arguments["vue"] == "tiers"

          du, au = periode!(arguments)
          titre = "du #{du} au #{au}#{" · #{entite.name}" if entite}"
          scope = JournalLine.joins(:journal_entry).where(journal_entries: { entry_date: du..au })
          scope = scope.where(journal_entries: { legal_entity_id: entite.id }) if entite
          arguments["vue"] == "analytique" ? analytique(scope, titre) : generale(scope, titre, arguments["classe"])
        end

        private

        def generale(scope, titre, classe)
          totaux = scope.group(:general_account_id).pluck(Arel.sql("general_account_id, SUM(debit_cents), SUM(credit_cents)"))
          comptes = GeneralAccount.where(id: totaux.map(&:first)).index_by(&:id)
          lignes = totaux.filter_map do |id, debit, credit|
            compte = comptes[id]
            next if compte.nil? || (classe.present? && compte.klass != classe.to_i)

            [compte, debit.to_i, credit.to_i]
          end.sort_by { |compte, _, _| compte.code }
          return "Balance #{titre} : aucune écriture." if lignes.empty?

          debit = lignes.sum { |l| l[1] }
          credit = lignes.sum { |l| l[2] }
          ["Balance générale #{titre}#{" · classe #{classe}" if classe.present?}",
           *lignes.map { |c, d, cr| "#{c} · débit #{euros(d)} · crédit #{euros(cr)} · solde #{solde_lisible(d - cr)}" },
           "Total · débit #{euros(debit)} · crédit #{euros(credit)} · " \
           "#{debit == credit ? 'équilibrée' : "ÉCART #{euros(debit - credit)}"}#{' (une classe seulement)' if classe.present?}"].join("\n")
        end

        def tiers(entite, arguments)
          au = arguments["au"].present? ? date!(arguments["au"], "au") : Date.current
          balance = Accounting::ThirdPartyBalance.new(
            side: arguments["cote"] == "clients" ? "customers" : "suppliers", as_of: au,
            entities: entite ? [entite] : LegalEntity.actives.ordered.to_a
          )
          titre = "Balance tiers · #{balance.label.downcase} au #{au}#{" · #{entite.name}" if entite}"
          lignes = balance.open_rows
          return "#{titre} : aucun solde." if lignes.empty?

          fournisseurs = balance.side == "suppliers"
          [titre,
           *lignes.map do |row|
             du = row.due_cents.negative? ? "#{euros(-row.due_cents)} d'avance" : euros(row.due_cents)
             "#{row.name} (#{row.accounts.map(&:code).join(', ')}) · ouverture #{euros(row.opening_due_cents)} · " \
               "débit #{euros(row.debit_cents)} · crédit #{euros(row.credit_cents)} · solde #{du}"
           end,
           "#{fournisseurs ? 'Nous devons' : 'On nous doit'} #{euros(balance.owed_cents)} · " \
           "avances #{euros(balance.advances_cents)} · net #{euros(balance.total_due_cents)}"].join("\n")
        end

        def analytique(scope, titre)
          totaux = scope.joins(:general_account).where(general_accounts: { klass: [6, 7] })
                        .where.not(GeneralAccount::APPROPRIATION_SQL)
                        .group(:team_id, "general_accounts.klass")
                        .pluck(Arel.sql("team_id, general_accounts.klass, SUM(debit_cents), SUM(credit_cents)"))
          return "Balance analytique #{titre} : aucune charge ni aucun produit." if totaux.empty?

          poles = Team.where(id: totaux.map(&:first).compact).index_by(&:id)
          lignes = totaux.group_by(&:first).map do |team_id, rangs|
            charges = rangs.select { |r| r[1] == 6 }.sum { |r| r[2].to_i - r[3].to_i }
            produits = rangs.select { |r| r[1] == 7 }.sum { |r| r[3].to_i - r[2].to_i }
            [team_id && (poles[team_id]&.name || "pôle ##{team_id}"), charges, produits]
          end
          ventiles, non_ventile = lignes.partition(&:first)
          sortie = ["Balance analytique #{titre}"]
          sortie += ventiles.sort_by(&:first).map { |nom, ch, pr| "#{nom} · charges #{euros(ch)} · produits #{euros(pr)} · résultat #{euros(pr - ch)}" }
          non_ventile.each { |_, ch, pr| sortie << "Non ventilé · charges #{euros(ch)} · produits #{euros(pr)} · résultat #{euros(pr - ch)}" }
          total_ch = lignes.sum { |l| l[1] }
          total_pr = lignes.sum { |l| l[2] }
          sortie << "Total · charges #{euros(total_ch)} · produits #{euros(total_pr)} · résultat #{euros(total_pr - total_ch)}"
          attente = CashEntry.pending.count
          sortie << "#{attente} ligne(s) de trésorerie encore à affecter : ces chiffres ne les comptent pas." if attente.positive?
          sortie.join("\n")
        end
      end
    end
  end
end
