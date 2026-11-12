module Finance
  # Les lignes d'un relevé de porteur en BROUILLON (Michael, 2026-11-12) :
  # corriger une rémunération, ou retirer une prestation. Un relevé émis se
  # rouvre d'abord (`CarrierStatementsController#reopen`).
  class CarrierStatementLinesController < Finance::AccountingBaseController
    before_action :get_line

    # Le montant se corrige sur la réservation, qui reste la source : la ligne
    # et le total du brouillon suivent (`ExperienceBooking#sync_draft_statement_line`).
    def update
      return refuse_issued unless @statement.draft?

      raw = params[:fee].to_s.strip
      if raw.blank? || raw.tr(",", ".") !~ /\A\d+(\.\d{1,2})?\z/
        return redirect_to finance_carrier_statement_path(@statement), alert: "Montant illisible : « #{raw} » (exemple : 40 ou 40,50)."
      end

      booking = @line.experience_booking
      PaperTrail.request(whodunnit: current_user&.email) { booking.update!(carrier_fee: raw) }
      redirect_to finance_carrier_statement_path(@statement),
                  notice: "#{@line.reload.display_label} : #{helpers.humanized_money_with_symbol(@line.fee)}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to finance_carrier_statement_path(@statement), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      pay = params[:pay].to_s != "0"
      CarrierStatements::RemoveLine.new(line: @line, pay: pay, whodunnit: current_user&.email).run!
      notice = if pay
                 "Ligne retirée : la prestation reviendra au prochain relevé."
               else
                 "Ligne retirée : la prestation passe à 0 € et ne sera pas payée."
               end
      redirect_to finance_carrier_statement_path(@statement), notice: notice
    rescue CarrierStatements::RemoveLine::Refused, ActiveRecord::RecordInvalid => e
      redirect_to finance_carrier_statement_path(@statement), alert: e.message
    end

    private

    def get_line
      @statement = CarrierStatement.find(params[:carrier_statement_id])
      @line = @statement.carrier_statement_lines.find(params[:id])
    end

    def refuse_issued
      redirect_to finance_carrier_statement_path(@statement),
                  alert: "Ce relevé est #{@statement.status_label.downcase} : rouvre-le en brouillon pour le corriger."
    end
  end
end
