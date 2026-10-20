require "csv"
require "zip"

module Accounting
  # Ce que le comptable emporte d'un exercice (revue expert-comptable du
  # 2026-10-20, priorité 6 : « livrer au comptable ce dont il a besoin ») : un
  # ZIP de fichiers CSV qu'il ouvre dans un tableur ou reprend dans son
  # logiciel, au lieu de ré-encoder.
  #
  # CSV « à la belge » : point-virgule, virgule décimale, UTF-8 avec BOM, pour
  # qu'Excel l'ouvre d'un double clic sans assistant d'import.
  class AccountantExport
    BOM = "﻿".freeze

    def initialize(fiscal_year)
      @fiscal_year = fiscal_year
      @entity = fiscal_year.legal_entity
    end

    def filename = "claudy-#{@entity.name.parameterize}-#{@fiscal_year.label}.zip"

    def files
      {
        "LISEZMOI.txt" => readme,
        "journaux.csv" => journals_csv,
        "grand-livre.csv" => ledger_csv,
        "balance.csv" => trial_balance_csv,
        "balance-tiers.csv" => third_party_balance_csv,
        "comptes-annuels.csv" => self.class.statements_csv(AnnualAccounts.new(@fiscal_year)),
        "immobilisations.csv" => fixed_assets_csv
      }
    end

    def zip
      Zip::OutputStream.write_buffer(StringIO.new) do |stream|
        files.each do |name, content|
          stream.put_next_entry(name)
          stream.write(content)
        end
      end.string
    end

    def self.amount(cents) = cents.nil? ? "" : format("%.2f", cents / 100.0).tr(".", ",")

    def self.csv(headers, rows)
      BOM + CSV.generate(col_sep: ";") do |csv|
        csv << headers
        rows.each { |row| csv << row }
      end
    end

    # Bilan, compte de résultats et affectation, rubrique par rubrique.
    def self.statements_csv(accounts)
      rows = []
      [["Bilan — actif", accounts.assets], ["Bilan — passif", accounts.liabilities],
       ["Compte de résultats", accounts.income_statement], ["Affectations", accounts.appropriation]].each do |part, list|
        list.each do |row|
          next if row.section?

          rows << [part, row.code, ("  " * row.level) + row.label, amount(row.amount_cents), amount(row.previous_cents)]
        end
      end
      rows << ["Bilan — actif", "20/58", "Total de l'actif", amount(accounts.total_assets_cents), amount(accounts.previous_total_assets_cents)]
      rows << ["Bilan — passif", "10/49", "Total du passif", amount(accounts.total_liabilities_cents), amount(accounts.previous_total_liabilities_cents)]
      csv(["Partie", "Code BNB", "Rubrique", "Exercice #{accounts.fiscal_year.label}", "Exercice #{accounts.previous_year&.label || 'précédent'}"], rows)
    end

    private

    def amount(cents) = self.class.amount(cents)

    def lines
      @lines ||= JournalLine.joins(:journal_entry)
                            .where(journal_entries: { fiscal_year_id: @fiscal_year.id })
                            .includes(:general_account, :third_party, :team, :analytic_account,
                                      journal_entry: %i[fiscal_year reversal_of])
                            .order("journal_entries.journal", "journal_entries.number", "journal_lines.id").to_a
    end

    def journals_csv
      self.class.csv(
        ["Journal", "Pièce", "Date", "Écriture", "Compte", "Intitulé du compte", "Tiers", "Pôle", "Analytique",
         "Débit", "Crédit", "Libellé de la ligne", "Origine", "Contre-passe", "Passée le"],
        lines.map do |line|
          entry = line.journal_entry
          [entry.journal_label, entry.reference, entry.entry_date.iso8601, entry.label, line.general_account.code,
           line.general_account.name, line.third_party&.name, line.team&.name, line.analytic_account&.code,
           amount(line.debit_cents), amount(line.credit_cents), line.label,
           entry.source_type && "#{entry.source_type} ##{entry.source_id}", entry.reversal_of&.reference,
           entry.posted_at&.to_date&.iso8601]
        end
      )
    end

    def opening = @opening ||= Balances.new(@entity).before(@fiscal_year.starts_on)

    def accounts_by_id
      @accounts_by_id ||= GeneralAccount.with_deleted do
        GeneralAccount.where(id: (opening.keys + lines.map(&:general_account_id)).uniq).index_by(&:id)
      end
    end

    def ledger_csv
      by_account = lines.group_by(&:general_account_id)
      rows = []
      accounts_by_id.values.sort_by(&:code).each do |account|
        running = opening[account.id]
        rows << [account.code, account.name, @fiscal_year.starts_on.iso8601, "", "Solde d'ouverture", "", "", "", amount(running)]
        by_account.fetch(account.id, []).sort_by { |line| [line.journal_entry.entry_date, line.journal_entry.id, line.id] }.each do |line|
          running += line.signed_cents
          entry = line.journal_entry
          rows << [account.code, account.name, entry.entry_date.iso8601, entry.reference, line.label.presence || entry.label,
                   line.third_party&.name, amount(line.debit_cents), amount(line.credit_cents), amount(running)]
        end
      end
      self.class.csv(%w[Compte Intitulé Date Pièce Libellé Tiers Débit Crédit Solde], rows)
    end

    def trial_balance_csv
      moves = lines.group_by(&:general_account_id)
      rows = accounts_by_id.values.sort_by(&:code).map do |account|
        list = moves.fetch(account.id, [])
        debit = list.sum(&:debit_cents)
        credit = list.sum(&:credit_cents)
        [account.code, account.name, amount(opening[account.id]), amount(debit), amount(credit),
         amount(opening[account.id] + debit - credit)]
      end
      self.class.csv(["Compte", "Intitulé", "Ouverture", "Débit de l'exercice", "Crédit de l'exercice", "Solde de clôture"], rows)
    end

    # Les soldes de fin d'exercice des comptes de tiers, tiers par tiers : ce
    # que le comptable pointe avant de valider les dettes et créances.
    def third_party_balance_csv
      sums = Balances.new(@entity).through(@fiscal_year.ends_on, by_third_party: true)
      accounts = GeneralAccount.with_deleted { GeneralAccount.where(id: sums.keys.map(&:first)).index_by(&:id) }
      third_parties = ThirdParty.where(id: sums.keys.map(&:last).compact).index_by(&:id)
      rows = sums.filter_map do |(account_id, third_party_id), cents|
        account = accounts[account_id]
        next if account.nil? || account.klass >= 6
        next unless account.reconcilable? || third_party_id

        [account.code, account.name, third_parties[third_party_id]&.name || "(sans tiers)", amount(cents)]
      end
      self.class.csv(["Compte", "Intitulé", "Tiers", "Solde (débit +, crédit −)"], rows.sort_by { |row| [row[0], row[2]] })
    end

    def fixed_assets_csv
      assets = FixedAsset.where(legal_entity_id: @entity.id).includes(:general_account, :depreciation_account, :depreciations, :team).ordered
      rows = assets.map do |asset|
        year_depreciation = asset.depreciation_for(@fiscal_year)&.amount_cents
        [asset.name, asset.general_account.code, asset.acquired_on.iso8601, amount(asset.acquisition_cents), asset.useful_life_years,
         amount(asset.prior_depreciation_cents), amount(year_depreciation), amount(asset.depreciated_cents),
         amount(asset.net_book_value_cents), asset.disposed_on&.iso8601, asset.team&.name]
      end
      self.class.csv(["Immobilisation", "Compte", "Acquise le", "Valeur d'acquisition", "Durée (ans)",
                      "Amorti avant Claudy", "Dotation #{@fiscal_year.label}", "Amortissements cumulés",
                      "Valeur nette comptable", "Sortie le", "Pôle"], rows)
    end

    def readme
      <<~TEXT
        Export Claudy — #{@entity.name} — exercice #{@fiscal_year.label}
        Du #{I18n.l(@fiscal_year.starts_on)} au #{I18n.l(@fiscal_year.ends_on)} · #{@fiscal_year.closed? ? 'exercice clôturé' : 'exercice OUVERT : chiffres provisoires'}
        Généré le #{I18n.l(Time.current, format: :long)}

        journaux.csv            toutes les écritures de l'exercice, ligne par ligne, par journal et numéro de pièce
        grand-livre.csv         chaque compte : solde d'ouverture, mouvements, solde qui court
        balance.csv             ouverture, débit, crédit et solde de clôture de chaque compte
        balance-tiers.csv       soldes de fin d'exercice par tiers (fournisseurs, clients, prêteurs, comptes courants)
        comptes-annuels.csv     bilan, compte de résultats et affectation au schéma abrégé de la BNB, avec l'exercice précédent
        immobilisations.csv     registre des immobilisations et amortissements

        Format : point-virgule, virgule décimale, UTF-8. Débit positif, crédit négatif dans les soldes.
        Ouverture : l'à-nouveau de l'exercice quand il existe ; sinon le cumul des exercices précédents
        (charges et produits repartent toujours de zéro).
      TEXT
    end
  end
end
