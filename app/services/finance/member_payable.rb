module Finance
  # Un compte de membre en crédit, présenté comme une dette de la file « À
  # payer » (Michael, 2026-10-30) : le cuisinier du batch cooking que la maison
  # doit payer n'était visible que sur l'écran Batch cooking.
  #
  # Ce n'est pas un document : pas de table, pas de `cash_allocations`. Le
  # virement se constate en rapprochant la sortie bancaire du compte
  # (`MatchMemberPayouts` → `RecordMemberPayout`), qui remet le solde à zéro —
  # la ligne quitte alors la file d'elle-même. D'où un rapproché toujours nul.
  #
  # La structure est la Fondation : c'est elle qui tient les comptes des
  # membres.
  class MemberPayable
    attr_reader :row

    delegate :member_account, :human, to: :row

    def initialize(row, legal_entity: nil)
      @row = row
      @legal_entity = legal_entity
    end

    def id = member_account.id

    def payable_amount_cents = row.due_cents
    def payable_beneficiary = member_account.name
    def payable_third_party = nil
    def payable_iban = row.iban
    def payable_communication = row.communication
    def payable_due_on = nil
    def payable_reference = member_account.code
    def payable_label = "Compte de membre en crédit #{member_account.code}"
    def payable_path = Rails.application.routes.url_helpers.finance_account_path(member_account)
    def payable_legal_entity = @legal_entity
    def legal_entity_id = @legal_entity&.id

    def allocated_cents = 0
    def remaining_cents = payable_amount_cents
    def payable_settled? = false
    def partially_paid? = false
    def payable_overdue?(_on = Date.current) = false
    def payable_days_late(_on = Date.current) = 0
    def payable_ready? = row.payable?
  end
end
