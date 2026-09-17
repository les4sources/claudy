module Consignments
  # La vérification d'un relevé de dépôt-vente (epic #248, phase 3).
  #
  # C'est le geste qui transforme une DÉCLARATION en DETTE. Tant que le relevé
  # n'est pas vérifié, ses totaux se recalculent à chaque affichage depuis les
  # lignes ; à la vérification, ils sont copiés dans les colonnes et ne bougent
  # plus — c'est sur eux qu'on paie, et un montant qui change après coup est un
  # montant qu'on ne peut plus opposer à personne.
  #
  # Le TAUX est figé lui aussi : un contrat renégocié en mars ne doit pas
  # réécrire ce qu'on a vérifié en janvier.
  class Verify < ServiceBase
    class BadStatus < StandardError; end
    class NoLines < StandardError; end

    def initialize(consignment_report:, verified_by: nil, whodunnit: nil)
      @report = consignment_report
      @verified_by = verified_by
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { consignment_report: @report&.id }) { verify }
    def run! = verify

    private

    def verify
      unless @report.declared? || @report.requested?
        raise BadStatus,
              "Seul un relevé déclaré se vérifie — celui-ci est #{@report.status_label.downcase}."
      end
      if @report.consignment_report_lines.empty?
        raise NoLines, "Ce relevé n'a aucune ligne — il n'y a rien à vérifier."
      end

      percent = @report.consignor.commission_percent
      gross = @report.consignment_report_lines.sum(&:amount_cents)
      commission = (gross * percent / 100.0).round

      PaperTrail.request(whodunnit: @whodunnit || "consignments") do
        @report.update!(
          status: "verified",
          commission_percent: percent,
          gross_cents: gross,
          commission_cents: commission,
          net_cents: gross - commission,
          verified_by: @verified_by,
          verified_at: Time.current
        )
      end

      @report.reload
    end
  end
end
