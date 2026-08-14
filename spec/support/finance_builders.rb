# Helpers de construction pour les specs Finances (issue #177).
#
# Pas de FactoryBot — la convention du dépôt est `Model.create!` explicite dans
# les `let`. Mais créer une écriture comptable demande une entité, un exercice,
# deux comptes et deux lignes : quarante lignes de setup par spec, répétées
# partout, finissent par cacher ce que la spec teste vraiment. Ces helpers ne
# masquent rien — ils construisent le décor minimal et le rendent nommable.
module FinanceBuilders
  def build_legal_entity(name: "Fondation de test", form: "foundation")
    LegalEntity.create!(name: name, form: form, vat_regime: "exempt")
  end

  def build_fiscal_year(entity, year: 2026, status: "open")
    FiscalYear.create!(legal_entity: entity, starts_on: Date.new(year, 1, 1),
                       ends_on: Date.new(year, 12, 31), status: status)
  end

  def build_general_account(code:, name: "Compte de test", klass: 5, nature: "asset")
    GeneralAccount.find_by(code: code) ||
      GeneralAccount.create!(code: code, name: name, klass: klass, nature: nature)
  end

  # Une écriture équilibrée minimale : un débit, un crédit, le même montant.
  def post_simple_entry(entity:, debit_account:, credit_account:, amount_cents: 10_000,
                        entry_date: Date.new(2026, 6, 15), journal: "misc", source: nil,
                        label: "Écriture de test")
    Accounting::PostDocument.new(
      legal_entity: entity, journal: journal, entry_date: entry_date, label: label, source: source,
      lines: [
        { account: debit_account, debit_cents: amount_cents },
        { account: credit_account, credit_cents: amount_cents }
      ]
    ).run!
  end
end
