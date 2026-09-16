module Finance
  # Le rapprochement d'une ligne bancaire ENTRANTE avec un versement Stripe
  # (epic #250, phase 2).
  #
  # Une ligne de 1 243,17 € sur le compte Triodos ne correspond à aucune facture :
  # elle est le versement d'un lot de paiements par carte, moins les commissions.
  # Tant que personne ne la relie à son versement, elle reste sur « À affecter »
  # et le rapprochement se fait de tête, à l'euro près, dans l'interface Stripe.
  #
  # **Ce service ne crée AUCUNE allocation** (invariant B4) : il propose, il
  # motive, un humain clique. Même patron que `MatchMemberPayouts` et
  # `MatchPurchaseInvoices`.
  #
  # Deux indices qui doivent tomber ENSEMBLE : le montant exact, et une date
  # d'arrivée à trois jours près. Le montant seul ne suffit pas — deux versements
  # de deux comptes Stripe peuvent coïncider ; la date seule encore moins.
  class MatchStripePayouts
    Match = Struct.new(:payout, :reason, :confidence, keyword_init: true)

    DATE_TOLERANCE = 3
    CONFIDENCE = 90

    def initialize(payouts: nil)
      @payouts = payouts
    end

    def for_entry(entry)
      return [] unless entry.amount_cents.positive?
      return [] if entry.cash_allocations.any?
      return [] unless entry.cash_account&.kind == "bank"

      candidats(entry).map do |payout|
        Match.new(payout: payout,
                  reason: "Versement #{payout.account_label} du #{I18n.l(payout.arrival_date, format: :short)}, " \
                          "pour exactement ce montant",
                  confidence: CONFIDENCE)
      end
    end

    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def candidats(entry)
      fenetre = (entry.entry_date - DATE_TOLERANCE)..(entry.entry_date + DATE_TOLERANCE)

      payouts.select do |payout|
        payout.amount_cents == entry.amount_cents &&
          payout.arrival_date.present? && fenetre.cover?(payout.arrival_date) &&
          !rapproche?(payout)
      end
    end

    # Les versements NON RAPPROCHÉS de la période, chargés une fois pour la page.
    def payouts
      @payouts ||= StripePayout.includes(:cash_account, :stripe_balance_transactions).to_a
    end

    # Un versement déjà rapproché ne se propose plus : le proposer une seconde
    # fois, c'est inviter à l'affecter deux fois.
    def rapproche?(payout)
      @rapproches ||= CashAllocation.where(document_type: "StripePayout").distinct.pluck(:document_id).to_set

      @rapproches.include?(payout.id)
    end
  end
end
