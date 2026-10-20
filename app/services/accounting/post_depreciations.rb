module Accounting
  # Passe les dotations aux amortissements d'un exercice : une écriture par
  # immobilisation, au dernier jour, 630 au débit (avec le pôle du bien) et le
  # compte d'amortissements actés au crédit.
  #
  # Ne passe que ce qui manque : relancer après avoir ajouté un bien au
  # registre ne double rien, l'index unique (bien, exercice) y veille.
  class PostDepreciations < ServiceBase
    class Refused < ServiceError; end

    Row = Data.define(:asset, :amount_cents) do
      def catch_up? = amount_cents > asset.annuity_cents
    end

    def initialize(fiscal_year:, whodunnit: nil)
      @fiscal_year = fiscal_year
      @whodunnit = whodunnit
    end

    def rows
      @rows ||= FixedAsset.where(legal_entity_id: @fiscal_year.legal_entity_id)
                          .includes(:depreciations, :general_account, :depreciation_account, :expense_account).ordered
                          .filter_map do |asset|
                            amount = asset.depreciation_due_cents(@fiscal_year)
                            Row.new(asset: asset, amount_cents: amount) if amount.positive?
                          end
    end

    def total_cents = rows.sum(&:amount_cents)

    def run
      catch_error(context: { fiscal_year: @fiscal_year.id }) { post }
    end

    def run!
      post
    end

    private

    def post
      raise Refused, "L'exercice #{@fiscal_year.label} est clôturé : on n'y passe plus de dotation." if @fiscal_year.closed?
      raise Refused, "Aucune dotation à passer sur #{@fiscal_year.label}." if rows.empty?

      PaperTrail.request(whodunnit: @whodunnit || "accounting") do
        ApplicationRecord.transaction do
          rows.each do |row|
            depreciation = FixedAssetDepreciation.create!(fixed_asset: row.asset, fiscal_year: @fiscal_year,
                                                          amount_cents: row.amount_cents)
            PostDocument.new(
              legal_entity: @fiscal_year.legal_entity, journal: "misc", entry_date: @fiscal_year.ends_on,
              label: "Dotation aux amortissements #{@fiscal_year.label} — #{row.asset.name}",
              source: depreciation, whodunnit: @whodunnit,
              lines: [
                { account: row.asset.expense_account, team: row.asset.team, debit_cents: row.amount_cents,
                  label: row.asset.name },
                { account: row.asset.depreciation_account, credit_cents: row.amount_cents, label: row.asset.name }
              ]
            ).run!
          end
        end
      end
      rows
    end
  end
end
