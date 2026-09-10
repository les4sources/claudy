module Accounting
  # L'écriture d'un relevé de partage de revenus (issue #247).
  #
  # Un reversement aux propriétaires est un ACHAT au sens comptable : les 4
  # Sources doivent la moitié de ce que l'hébergement a rapporté à quelqu'un
  # d'extérieur. D'où le journal `purchases`, la charge au débit et la dette au
  # crédit du 440000, portée par le tiers — c'est cette ligne-là qu'on lettrera
  # contre le virement quand il partira.
  #
  # Idempotent par construction : `PostDocument` rend l'écriture existante quand
  # le même document repasse dans le même journal.
  class PostRevenueShareStatement < ServiceBase
    class MissingAccount < StandardError; end

    EXPENSE_CODE = GeneralAccount::REVENUE_SHARE_CODE
    SUPPLIER_CODE = "440000".freeze
    DEFAULT_ENTITY = "Fondation Les 4 Sources".freeze

    def initialize(statement:, whodunnit: nil)
      @statement = statement
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { revenue_share_statement: @statement.id }) { post }
    end

    def run! = post

    private

    def post
      PostDocument.new(
        legal_entity: legal_entity,
        journal: "purchases",
        entry_date: @statement.period_to,
        label: label,
        source: @statement,
        whodunnit: @whodunnit,
        lines: [
          { account: expense_account, label: label, debit_cents: @statement.share_cents },
          { account: supplier_account, third_party: third_party, label: label,
            credit_cents: @statement.share_cents }
        ]
      ).run!
    end

    def agreement = @statement.revenue_share_agreement

    def label
      "Reversement #{agreement.lodging&.name} — #{@statement.period_label} — #{agreement.beneficiary_name}"
    end

    def legal_entity
      LegalEntity.find_by(name: DEFAULT_ENTITY) || LegalEntity.actives.ordered.first ||
        raise(MissingAccount, "Aucune entité juridique — lance `rake accounting:seed_reference`.")
    end

    def expense_account = fetch_account(EXPENSE_CODE)
    def supplier_account = fetch_account(SUPPLIER_CODE)

    def fetch_account(code)
      GeneralAccount.find_by(code: code) ||
        raise(MissingAccount,
              "Le compte #{code} n'existe pas — lance `rake accounting:seed_reference`.")
    end

    # Le tiers du bénéficiaire, créé à la volée s'il manque puis MÉMORISÉ sur
    # l'accord : le second trimestre doit retomber sur le même tiers, sinon le
    # 440000 se peuple d'homonymes et plus personne ne sait à qui on doit quoi.
    def third_party
      return agreement.beneficiary_third_party if agreement.beneficiary_third_party.present?

      party = ThirdParty.find_by(code: third_party_code) ||
              ThirdParty.create!(code: third_party_code, name: agreement.beneficiary_name,
                                 kind: "supplier")
      agreement.update_column(:beneficiary_third_party_id, party.id)
      party
    end

    def third_party_code
      @third_party_code ||= begin
        base = agreement.beneficiary_name.to_s.parameterize(separator: "").upcase.first(10)
        base = "BENEF" if base.blank?
        "#{base}#{agreement.id}"
      end
    end
  end
end
