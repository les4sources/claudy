module Consignments
  # Le relevé est-il réglé ? (epic #248, phase 3)
  #
  # On ne coche pas « réglé » : on le CONSTATE, et de deux façons selon le mode
  # du contrat.
  #
  #   · mode `transfer` — les lignes de trésorerie affectées sur le `440000`
  #     avec ce relevé en `document` couvrent le net ;
  #   · mode `invoice`  — la facture d'achat liée est elle-même `paid`.
  #
  # Et dans les deux sens : si on défait l'affectation, ou si la facture
  # redevient « à payer », le relevé redevient « vérifié ». Un état qui ne sait
  # que monter est un état faux.
  class RefreshSettlement < ServiceBase
    def initialize(consignment_report:)
      @report = consignment_report
    end

    def run = catch_error(context: { consignment_report: @report&.id }) { refresh }
    def run! = refresh

    private

    def refresh
      return @report if @report.blank?
      return @report unless %w[verified settled].include?(@report.status)

      if settled?
        return @report if @report.settled?

        @report.update!(status: "settled", settled_on: settled_on)
      elsif @report.settled?
        @report.update!(status: "verified", settled_on: nil)
      end

      @report.reload
    end

    def settled?
      @report.consignor&.invoice? ? invoice_paid? : allocations_cover_net?
    end

    def invoice_paid? = @report.purchase_invoice&.paid?

    def allocations_cover_net?
      net = @report.net_cents.to_i
      net.positive? && @report.cash_allocations.sum(:amount_cents).abs >= net
    end

    def settled_on
      return @report.purchase_invoice&.paid_on || Date.current if @report.consignor&.invoice?

      @report.cash_allocations.includes(:cash_entry)
             .filter_map { |a| a.cash_entry&.entry_date }.max || Date.current
    end
  end
end
