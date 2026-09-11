module Finance
  # Le virement qui solde le compte d'un membre (epic #246, phase 2).
  #
  # Un cuisinier de batch cooking — un enfant compris — accumule un solde EN SA
  # FAVEUR (négatif) sur son compte personnel. Le payer, c'est deux gestes qui
  # doivent tomber ensemble : une écriture `payout` positive sur son compte, qui
  # ramène le solde vers zéro, et l'affectation de la ligne bancaire sortante sur
  # les dettes envers les membres (`440000`), avec son tiers.
  #
  # Les faire séparément laisserait toujours une des deux moitiés en plan : un
  # compte soldé sans ligne bancaire affectée, ou une dépense affectée sur un
  # compte qui reste créditeur.
  class RecordMemberPayout < ServiceBase
    class NotCreditor < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end
    class WrongDirection < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(member_account:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @account = member_account
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i&.abs
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { member_account: @account&.id }) { record }
    def run! = record

    private

    def record
      raise MissingAccount, "Aucun compte membre à payer." if @account.blank?
      raise WrongDirection, "Un virement se paie depuis une ligne SORTANTE." unless @entry.amount_cents.negative?

      du = -@account.balance_cents
      raise NotCreditor, "Ce compte n'est pas en faveur de #{@account.name} — il n'y a rien à virer." unless du.positive?

      montant = @amount_cents || du
      if montant > du
        raise TooMuch,
              "Ce compte n'attend que #{Money.new(du, 'EUR').format} — " \
              "virer #{Money.new(montant, 'EUR').format} le rendrait débiteur."
      end

      PaperTrail.request(whodunnit: @whodunnit || "member_payout") do
        ApplicationRecord.transaction do
          @entry.lock!

          @account.account_entries.create!(
            entry_date: @entry.entry_date,
            kind: "payout",
            flow: "other",
            label: "Virement du #{I18n.l(@entry.entry_date, format: :short)}",
            amount_cents: montant,
            idempotency_key: "payout:cash_entry:#{@entry.id}:account:#{@account.id}"
          )

          @entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: @entry.cash_account.legal_entity,
            third_party: third_party,
            document: @account,
            amount_cents: -montant,
            label: "Virement à #{@account.name}"
          )

          if @entry.reload.fully_allocated?
            Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
          end
        end
      end

      @account.reload
    end

    # Le tiers est celui de la PERSONNE : c'est la ligne 440000 qu'on lettrera
    # un jour contre ce virement.
    def third_party
      return nil if @account.human.blank?

      ThirdParty.for_human!(@account.human)
    end

    def supplier_account
      @supplier_account ||= GeneralAccount.find_by(code: SUPPLIER_CODE) ||
                            raise(MissingAccount,
                                  "Le compte des dettes fournisseurs #{SUPPLIER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
