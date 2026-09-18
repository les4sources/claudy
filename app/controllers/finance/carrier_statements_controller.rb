module Finance
  # Les relevés de rémunération des porteurs d'activité (epic #244, phase 3).
  #
  # Deux gestes, et l'ordre compte : GÉNÉRER produit un brouillon qu'on relit,
  # ÉMETTRE en fait un document — figé, comptabilisé, envoyé. Le second est
  # irréversible, d'où le premier. Même forme que les relevés de reversement.
  class CarrierStatementsController < Finance::AccountingBaseController
    before_action :get_statement, only: %i[show issue destroy]

    breadcrumb "Porteurs", :finance_carrier_statements_path, match: :exact

    # Par porteur : ce qui a été tenu et pas encore relevé, et ses relevés.
    def index
      @rows = carriers.map do |human|
        selection = CarrierStatements::Selection.new(human: human)
        { human: human, pending: selection.bookings, pending_cents: selection.total_fee_cents,
          statements: CarrierStatement.where(human: human).recent_first.to_a }
      end
      @rows.reject! { |row| row[:pending].empty? && row[:statements].empty? }
      @default_from, @default_to = CarrierStatements::Generate.default_period
    end

    def show
      @human = @statement.human
      @lines = @statement.carrier_statement_lines.chronological.includes(experience_booking: :experience_availability)
    end

    def create
      human = Human.find(params[:human_id])
      service = CarrierStatements::Generate.new(
        human: human,
        period_from: parsed_date(params[:period_from]),
        period_to: parsed_date(params[:period_to]),
        whodunnit: current_user&.email
      )

      if service.run
        redirect_to finance_carrier_statement_path(service.statement),
                    notice: "Relevé généré en brouillon : relis-le avant de l'émettre."
      else
        redirect_to finance_carrier_statements_path,
                    alert: service.error_message(default: "Génération impossible.")
      end
    end

    def issue
      service = CarrierStatements::Issue.new(statement: @statement, whodunnit: current_user&.email)

      if service.run
        notice = if @statement.reload.sent_at.present?
                   "Relevé émis et envoyé à #{@statement.human.email}."
                 else
                   "Relevé émis. Ce porteur n'a pas d'adresse email : partage le lien de la page à la main."
                 end
        redirect_to finance_carrier_statement_path(@statement), notice: notice
      else
        redirect_to finance_carrier_statement_path(@statement),
                    alert: service.error_message(default: "Émission impossible.")
      end
    end

    # On ne supprime QUE des brouillons : un relevé émis est comptabilisé, il se
    # corrige par contre-passation, pas en disparaissant.
    def destroy
      unless @statement.draft?
        return redirect_to finance_carrier_statement_path(@statement),
                           alert: "Un relevé émis ne se supprime pas : passe par une contre-passation."
      end

      # Les lignes partent POUR DE BON, pas en soft-delete : l'index unique sur
      # `experience_booking_id` est inconditionnel, une ligne fantôme
      # interdirait de jamais relever à nouveau ces prestations.
      CarrierStatement.transaction do
        @statement.carrier_statement_lines.destroy_all
        @statement.soft_delete!(validate: false)
      end
      redirect_to finance_carrier_statements_path,
                  notice: "Brouillon supprimé : ses prestations redeviennent disponibles."
    end

    private

    def get_statement
      @statement = CarrierStatement.find(params[:id])
    end

    # Les humains qui portent au moins une activité. On ne liste pas tout le
    # collectif : l'écran répond à « qui dois-je payer », pas « qui existe ».
    def carriers
      Human.where(id: Experience.where.not(human_id: nil).select(:human_id)).order(:name)
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
