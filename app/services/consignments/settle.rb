module Consignments
  # « Régler le relevé » (epic #248, phase 3), en mode VIREMENT.
  #
  # Ce geste ne paie rien : il comptabilise la dette et met le relevé dans la
  # file « À payer ». Le paiement, lui, est un rapprochement — c'est la ligne
  # bancaire affectée sur le `440000` qui fera passer le relevé en `settled`
  # (`Consignments::RefreshSettlement`).
  #
  # En mode `invoice`, il n'y a rien à comptabiliser ici : c'est la facture
  # d'achat de l'artisan qui porte la dette, et son paiement qui solde le relevé.
  class Settle < ServiceBase
    class BadStatus < StandardError; end
    class WrongMode < StandardError; end

    def initialize(consignment_report:, whodunnit: nil)
      @report = consignment_report
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { consignment_report: @report&.id }) { settle }
    def run! = settle

    private

    def settle
      unless @report.verified?
        raise BadStatus,
              "Seul un relevé vérifié se règle — celui-ci est #{@report.status_label.downcase}."
      end
      unless @report.consignor.transfer?
        raise WrongMode,
              "#{@report.consignor.name} facture ses ventes : lie la facture d'achat au relevé " \
              "plutôt que de générer une écriture."
      end

      PaperTrail.request(whodunnit: @whodunnit || "consignments") do
        ApplicationRecord.transaction do
          Accounting::PostConsignmentReport.new(consignment_report: @report,
                                                whodunnit: @whodunnit).run!
          @report.update!(posted_at: Time.current,
                          legal_entity: @report.legal_entity || LegalEntity.actives.ordered.first)
        end
      end

      @report.reload
    end
  end
end
