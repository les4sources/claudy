module Accounting
  # L'écriture d'un relevé de porteur (epic #244, décision 5).
  #
  # Ce que les 4 Sources doivent à quelqu'un qui a animé chez elles est un ACHAT
  # au sens comptable. D'où le journal `purchases`, la charge au débit et la
  # dette au crédit du `440000` avec le tiers du porteur — c'est cette ligne-là
  # qu'on lettrera contre le virement.
  #
  # La charge est ventilée PAR PÔLE (décision 6) : une ligne de débit par pôle
  # d'activité, parce que le coût des porteurs suit le pôle qui les a fait
  # travailler. Les activités sans pôle se regroupent sur une ligne sans pôle.
  #
  # Idempotent : `PostDocument` rend l'écriture existante quand le même document
  # repasse dans le même journal.
  class PostCarrierStatement < ServiceBase
    class MissingAccount < StandardError; end
    class NothingToPost < StandardError; end

    EXPENSE_CODE = GeneralAccount::CONTRIBUTOR_FEE_CODE
    SUPPLIER_CODE = "440000".freeze
    DEFAULT_ENTITY = "Fondation Les 4 Sources".freeze

    def initialize(statement:, whodunnit: nil)
      @statement = statement
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { carrier_statement: @statement&.id }) { post }
    def run! = post

    private

    def post
      raise NothingToPost, "Ce relevé n'a aucune ligne." if @statement.carrier_statement_lines.empty?

      PostDocument.new(
        legal_entity: legal_entity,
        journal: "purchases",
        entry_date: @statement.period_to,
        label: label,
        source: @statement,
        whodunnit: @whodunnit,
        lines: expense_lines + [supplier_line]
      ).run!
    end

    # Une ligne de charge par pôle, pour que la lecture analytique dise quel
    # pôle a consommé quelle rémunération.
    def expense_lines
      lines = @statement.carrier_statement_lines.includes(experience_booking: { experience_availability: { experience: :team } })

      lines.group_by { |line| line.experience_booking.experience&.team }
           .map do |team, group|
             {
               account: expense_account,
               team: team,
               label: [label, team&.name].compact_blank.join(" · "),
               debit_cents: group.sum { |l| l.fee_cents.to_i }
             }
           end
    end

    def supplier_line
      {
        account: supplier_account,
        third_party: ThirdParty.for_human!(@statement.human),
        label: @statement.human.name,
        credit_cents: @statement.total_fee_cents
      }
    end

    def label
      "Relevé d'activités #{@statement.human.name} — #{@statement.period_label}"
    end

    def legal_entity
      LegalEntity.find_by(name: DEFAULT_ENTITY) || LegalEntity.actives.ordered.first ||
        raise(MissingAccount, "Aucune entité juridique — lance `rake accounting:seed_reference`.")
    end

    def expense_account = fetch_account(EXPENSE_CODE)
    def supplier_account = fetch_account(SUPPLIER_CODE)

    def fetch_account(code)
      GeneralAccount.find_by(code: code) ||
        raise(MissingAccount, "Le compte #{code} n'existe pas — lance `rake accounting:seed_reference`.")
    end
  end
end
