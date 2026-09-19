module Finance
  # Le virement entrant qui éteint la dette d'un habitant (issue #349).
  #
  # Miroir exact de `RecordMemberPayout` : là-bas une ligne SORTANTE solde un
  # compte créditeur, ici une ligne ENTRANTE éteint une dette. Et comme là-bas,
  # c'est deux gestes qui doivent tomber ENSEMBLE, dans la même transaction :
  #
  #   1. le règlement sur le compte courant — une écriture négative + son
  #      `AccountSettlement`, produits par `RecordSettlement` (on ne duplique pas
  #      cette logique : le lot interdit les doubles écritures, et deux chemins
  #      pour créer un règlement finiraient par diverger) ;
  #   2. l'affectation de la ligne bancaire sur le 400000 « Clients », calquée
  #      sur ce que fait `RecordMemberPayout` avec le 440000.
  #
  # Les faire séparément laisserait toujours une moitié en plan : une dette
  # éteinte sans ligne affectée — la file « À affecter » ne redescend jamais à
  # zéro —, ou une ligne affectée sur un compte qui reste débiteur, c'est-à-dire
  # exactement ce qu'on essaie de réparer.
  #
  # Rien ici ne se déclenche tout seul : c'est un clic humain sur une proposition
  # de `MatchMemberSettlements` qui appelle ce service.
  class RecordMemberSettlement < ServiceBase
    class NotDebtor < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end
    class WrongDirection < StandardError; end

    CUSTOMER_CODE = "400000".freeze

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
      raise MissingAccount, "Aucun compte membre à créditer." if @account.blank?
      raise WrongDirection, "Un règlement s'encaisse depuis une ligne ENTRANTE." unless @entry.amount_cents.positive?

      du = @account.balance_cents
      raise NotDebtor, "#{@account.name} ne doit rien — il n'y a pas de dette à éteindre." unless du.positive?

      montant = @amount_cents || [@entry.amount_cents, du].min
      if montant > du
        raise TooMuch,
              "Ce compte ne doit que #{Money.new(du, 'EUR').format} — " \
              "y imputer #{Money.new(montant, 'EUR').format} le mettrait en crédit."
      end

      PaperTrail.request(whodunnit: @whodunnit || "member_settlement") do
        ApplicationRecord.transaction do
          @entry.lock!

          Finance::RecordSettlement.new(
            member_account: @account,
            amount_cents: montant,
            received_on: @entry.entry_date,
            method: "bank_transfer",
            received_channel: "bank",
            # La communication brute du virement, telle que l'habitant l'a
            # tapée : c'est elle qu'on relira dans six mois pour savoir de quoi
            # ce règlement parlait.
            reference: @entry.communication.presence,
            notes: "Rapproché de la ligne bancaire ##{@entry.id} du " \
                   "#{I18n.l(@entry.entry_date, format: :short)} (#{@entry.label})",
            whodunnit: @whodunnit,
            idempotency_key: idempotency_key
          ).run!

          @entry.cash_allocations.create!(
            general_account: customer_account,
            legal_entity: @entry.cash_account.legal_entity,
            third_party: third_party,
            document: @account,
            amount_cents: montant,
            label: "Règlement de #{@account.name}"
          )

          if @entry.reload.fully_allocated?
            Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
          end
        end
      end

      @account.reload
    end

    # Rejouer la même ligne sur le même compte ne doit pas créer un second
    # règlement. L'unicité est tenue en BASE, par l'index sur
    # `account_entries.idempotency_key` : un garde applicatif se ferait doubler
    # par deux clics simultanés, pas la contrainte.
    def idempotency_key = "settlement:cash_entry:#{@entry.id}:account:#{@account.id}"

    # Le tiers est celui de la PERSONNE, quand le compte en désigne une : c'est
    # la ligne 400000 qu'on lettrera contre ce virement. Un compte de ménage n'a
    # pas de tiers — le document suffit à le retrouver.
    def third_party
      return nil if @account.human.blank?

      ThirdParty.for_human!(@account.human)
    end

    def customer_account
      @customer_account ||= GeneralAccount.find_by(code: CUSTOMER_CODE) ||
                            raise(MissingAccount,
                                  "Le compte clients #{CUSTOMER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
