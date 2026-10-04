module Shop
  # Saisir — et, quand on le dit, valider — le contrôle mensuel d'un carnet
  # (epic #359, phase 5).
  #
  # Un brouillon s'enregistre autant de fois qu'on veut : on additionne les
  # feuilles en plusieurs fois. La validation fige ce que la banque a reçu et
  # l'écart, exactement comme `Finance::RecordCashCount` fige celui d'un
  # comptage : c'est le seul endroit qui écrit ces deux chiffres.
  class RecordMonthlyCheck < ServiceBase
    class AlreadyValidated < StandardError; end

    def initialize(channel:, month:, attributes:, validate: false, user: nil)
      @channel = channel.to_s
      @month = month.beginning_of_month
      @attributes = attributes
      @validate = validate
      @user = user
    end

    def run = catch_error(context: { channel: @channel, month: @month }) { record }
    def run! = record

    private

    def record
      check = ShopMonthlyCheck.find_or_initialize_by(channel: @channel, period_month: @month)
      raise AlreadyValidated, "Le contrôle #{check.notebook_label} de #{check.period_label} est déjà validé." if check.validated?

      check.assign_attributes(@attributes.slice(:sheets_total_cents, :transfer_total_cents, :cash_total_cents,
                                                :sheet_numbers, :notes))

      if @validate
        received = check.live_bank_received_cents
        check.assign_attributes(
          status: "validated", validated_at: Time.current, validated_by: @user,
          bank_received_cents: received,
          gap_cents: check.sheets_total_cents.to_i - received - check.cash_total_cents.to_i
        )
      end

      check.save!
      check
    end
  end
end
