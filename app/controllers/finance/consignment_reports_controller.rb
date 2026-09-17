require "csv"

module Finance
  # Comptabilité > Dépôt-vente (epic #248, phase 2).
  #
  # Le tableau de bord du mois : qui a été sollicité, qui a déclaré, qui reste
  # muet. C'est la question que l'administration se pose le 5 du mois, et
  # jusqu'ici elle n'avait qu'un fil d'emails pour y répondre.
  #
  # La fiche d'un relevé, sa vérification et son règlement sont arrivés en
  # phase 3 : on y corrige les lignes tant que rien n'est figé, on fige, puis on
  # règle — par virement, ou en liant la facture que l'artisan a envoyée.
  class ConsignmentReportsController < Finance::AccountingBaseController
    before_action :get_report, only: %i[show update resend verify settle link_invoice unlink_invoice]

    breadcrumb "Dépôt-vente", :finance_consignment_reports_path, match: :exact

    def index
      @month = parsed_month
      @reports = ConsignmentReport.for_month(@month)
                                  .includes(:consignor, :consignment_report_lines)
                                  .joins(:consignor).merge(Consignor.ordered)
      # Les artisans dont le contrat court ce mois-là et qui n'ont pas encore de
      # relevé : sans eux, l'écran dirait « tout le monde a déclaré » alors que
      # le rake n'a simplement pas été lancé.
      @missing = Consignor.actives.ordered.select { |c| c.running_on?(@month.end_of_month) } -
                 @reports.map(&:consignor)
    end

    # La fiche d'un relevé : les lignes déclarées, les totaux, l'écriture liée et
    # ce qu'il reste à faire.
    def show
      breadcrumb @report.reference, finance_consignment_report_path(@report), match: :exact

      @lines = @report.consignment_report_lines.ordered
      # Les factures d'achat candidates en mode « l'artisan facture » : celles du
      # tiers de l'artisan, ou de n'importe quel tiers quand il n'en a pas — on
      # ne devine pas à sa place, on propose et il choisit.
      @candidate_invoices = candidate_invoices
    end

    # Correction des lignes par l'administration, tant que rien n'est figé.
    # Toute modification est tracée par PaperTrail : le relevé est ce que
    # l'artisan a déclaré, ce qu'on y touche doit rester lisible.
    def update
      unless @report.editable_by_admin?
        redirect_to finance_consignment_report_path(@report),
                    alert: "Ce relevé est #{@report.status_label.downcase} — ses lignes ne se corrigent plus."
        return
      end

      if @report.update(report_params)
        redirect_to finance_consignment_report_path(@report), notice: "Relevé mis à jour."
      else
        @lines = @report.consignment_report_lines.ordered
        @candidate_invoices = candidate_invoices
        flash.now[:alert] = @report.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    # Figer les totaux et le taux : c'est le geste qui transforme une
    # déclaration en dette.
    def verify
      Consignments::Verify.new(consignment_report: @report, verified_by: current_user,
                               whodunnit: current_user&.email).run!
      redirect_to finance_consignment_report_path(@report),
                  notice: "Relevé vérifié — #{helpers.humanized_money_with_symbol(Money.new(@report.reload.net_cents, 'EUR'))} dus à #{@report.consignor.name}."
    rescue Consignments::Verify::BadStatus, Consignments::Verify::NoLines,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_consignment_report_path(@report), alert: e.message
    end

    # Comptabiliser la dette et mettre le relevé dans la file « À payer ».
    # Ce geste ne paie rien : le paiement est un rapprochement.
    def settle
      Consignments::Settle.new(consignment_report: @report, whodunnit: current_user&.email).run!
      redirect_to finance_consignment_report_path(@report),
                  notice: "Écriture générée — le relevé attend son virement dans « À payer »."
    rescue Consignments::Settle::BadStatus, Consignments::Settle::WrongMode,
           Accounting::PostConsignmentReport::MissingAccount,
           Accounting::PostConsignmentReport::MissingEntity,
           Accounting::PostConsignmentReport::NothingToPost,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_consignment_report_path(@report), alert: e.message
    end

    # Mode « l'artisan facture » : on relie la facture d'achat au relevé. Son
    # paiement le soldera — on ne coche jamais « réglé » à côté.
    def link_invoice
      invoice = PurchaseInvoice.find_by(id: params[:purchase_invoice_id])

      if invoice.nil?
        redirect_to finance_consignment_report_path(@report), alert: "Choisis une facture."
      elsif @report.update(purchase_invoice: invoice)
        Consignments::RefreshSettlement.new(consignment_report: @report.reload).run!
        redirect_to finance_consignment_report_path(@report),
                    notice: "Facture #{invoice.payable_reference} liée au relevé."
      else
        redirect_to finance_consignment_report_path(@report),
                    alert: @report.errors.full_messages.to_sentence
      end
    end

    def unlink_invoice
      @report.update!(purchase_invoice: nil)
      Consignments::RefreshSettlement.new(consignment_report: @report.reload).run!
      redirect_to finance_consignment_report_path(@report), notice: "Facture détachée du relevé."
    end

    # Le récapitulatif annuel par artisan, en CSV : ce que l'administration
    # envoie au comptable en fin d'exercice, et ce que l'artisan demande pour sa
    # propre déclaration.
    def yearly
      @year = params[:year].presence&.to_i || Date.current.year
      @rows = yearly_rows(@year)

      respond_to do |format|
        format.html
        format.csv do
          send_data yearly_csv(@rows),
                    filename: "depot-vente-#{@year}.csv",
                    type: "text/csv; charset=utf-8"
        end
      end
    end

    # Relance manuelle — le rake est mensuel, mais un artisan perd son mail.
    def resend
      if @report.consignor.email.blank?
        redirect_to finance_consignment_reports_path(month: @report.period_month.strftime("%Y-%m")),
                    alert: "#{@report.consignor.name} n'a pas d'adresse email — le lien est à donner à la main."
        return
      end

      ConsignmentMailer.monthly_request(@report).deliver_later
      @report.update_column(:requested_at, Time.current)

      redirect_to finance_consignment_reports_path(month: @report.period_month.strftime("%Y-%m")),
                  notice: "Demande renvoyée à #{@report.consignor.email}."
    end

    private

    def get_report
      @report = ConsignmentReport.find(params[:id])
    end

    def report_params
      params.require(:consignment_report).permit(
        :notes,
        consignment_report_lines_attributes: %i[id label quantity unit_price position _destroy]
      ).tap do |permitted|
        Array(permitted[:consignment_report_lines_attributes]&.values).each do |line|
          next if line[:unit_price].blank?

          line[:unit_price_cents] = (line.delete(:unit_price).to_s.tr(",", ".").to_f * 100).round
        end
      end
    end

    # Les factures candidates pour le mode « l'artisan facture ». On privilégie
    # celles du tiers de l'artisan ; sans tiers connu, on propose les factures
    # non encore liées plutôt que rien.
    def candidate_invoices
      return PurchaseInvoice.none unless @report.consignor.invoice?

      scope = PurchaseInvoice.includes(:third_party).ordered.limit(50)
      tiers = @report.consignor.third_party ||
              (@report.consignor.human && ThirdParty.find_by(human_id: @report.consignor.human_id))
      tiers ? scope.where(third_party_id: tiers.id) : scope
    end

    # Une ligne par artisan : ce qu'il a vendu, ce que la maison a gardé, ce
    # qu'il a touché. Les relevés non vérifiés y entrent avec leurs totaux
    # vivants — un récapitulatif qui tairait les mois pas encore traités
    # donnerait un chiffre faux à qui le lit.
    def yearly_rows(year)
      reports = ConsignmentReport.where(period_month: Date.new(year, 1, 1)..Date.new(year, 12, 31))
                                 .includes(:consignor, :consignment_report_lines)
                                 .ordered

      reports.group_by(&:consignor).map do |consignor, list|
        {
          consignor: consignor,
          reports: list.size,
          settled: list.count(&:settled?),
          gross_cents: list.sum(&:displayed_gross_cents),
          commission_cents: list.sum(&:displayed_commission_cents),
          net_cents: list.sum(&:displayed_net_cents)
        }
      end.sort_by { |row| row[:consignor].name.to_s }
    end

    # Trois choix dictés par Excel en Belgique, comme les autres exports du
    # projet : séparateur point-virgule, BOM UTF-8 (sans lui, Excel lit les
    # accents de travers), virgule décimale.
    BOM = "\uFEFF".freeze

    def yearly_csv(rows)
      BOM + CSV.generate(col_sep: ";") do |csv|
        csv << ["Artisan", "Relevés", "Réglés", "Ventes brutes (€)", "Commission (€)", "Net artisan (€)"]
        rows.each do |row|
          csv << [row[:consignor].name, row[:reports], row[:settled],
                  euros(row[:gross_cents]), euros(row[:commission_cents]), euros(row[:net_cents])]
        end
        csv << ["Total", rows.sum { |r| r[:reports] }, rows.sum { |r| r[:settled] },
                euros(rows.sum { |r| r[:gross_cents] }),
                euros(rows.sum { |r| r[:commission_cents] }),
                euros(rows.sum { |r| r[:net_cents] })]
      end
    end

    def euros(cents) = format("%.2f", cents.to_i / 100.0).tr(".", ",")

    def parsed_month(raw = params[:month])
      raw.present? ? Date.parse(raw.length == 7 ? "#{raw}-01" : raw).beginning_of_month : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def accounting_secondary = "consignment_reports"
  end
end
