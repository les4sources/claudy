module Finance
  # Règlements reçus (issue #160).
  class SettlementsController < Finance::BaseController
    before_action :get_account

    def create
      result = Finance::RecordSettlement.new(
        member_account: @account,
        amount_cents: cents_from(params.dig(:settlement, :amount)),
        received_on: params.dig(:settlement, :received_on).presence || Date.current,
        method: params.dig(:settlement, :method).presence || "bank_transfer",
        received_channel: params.dig(:settlement, :received_channel).presence || "bank",
        reference: params.dig(:settlement, :reference),
        notes: params.dig(:settlement, :notes),
        whodunnit: current_user&.email
      ).run

      if result
        redirect_to finance_account_path(@account), notice: "Règlement enregistré."
      else
        redirect_to finance_account_path(@account), alert: "Le règlement n'a pas pu être enregistré."
      end
    end

    private

    def get_account
      @account = MemberAccount.find(params[:account_id])
    end

    def cents_from(raw)
      value = raw.to_s.strip.tr(",", ".")
      return 0 unless value.match?(/\A\d+(\.\d+)?\z/)

      (value.to_f * 100).round
    end

    def finance_secondary = "accounts"
  end
end
