module Public
  # Page de sélection d'activités envoyée au client 1 mois avant son arrivée.
  # Accessible via un lien token unique dans l'email (sans Devise).
  class ActivitySelectionsController < Public::BaseController
    layout "public_sheet"

    before_action :load_stay

    def show
      @availabilities = availabilities_for_stay
    end

    def create
      selections = (params[:activities] || {}).values.select { |s| s[:participants].to_i > 0 }

      ExperienceBooking.transaction do
        selections.each do |sel|
          avail_id = sel[:availability_id].to_i
          next if avail_id.zero?

          booking = ExperienceBooking.find_or_initialize_by(
            stay_id: @stay.id,
            experience_availability_id: avail_id
          )
          booking.participants = sel[:participants].to_i
          booking.status = "pending" if booking.new_record?
          booking.save!
        end
      end

      ActivitySelectionMailer.confirmation(@stay).deliver_later
      ActivitySelectionMailer.animateur_notification(@stay).deliver_later

      redirect_to public_activity_selection_path(@stay.activity_selection_token),
                  notice: "Vos activités ont été enregistrées. Les animateurs seront contactés pour confirmer."
    rescue ActiveRecord::RecordInvalid => e
      @availabilities = availabilities_for_stay
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end

    private

    def load_stay
      @stay = Stay.find_by!(activity_selection_token: params[:token])
    rescue ActiveRecord::RecordNotFound
      render plain: "Lien invalide ou expiré.", status: :not_found
    end

    def availabilities_for_stay
      ExperienceAvailability
        .includes(:experience, :experience_bookings)
        .for_date_range(@stay.arrival_date, @stay.departure_date)
        .joins(:experience)
        .where(experiences: { deleted_at: nil })
        .where.not(experiences: { name: "Pizza Party" })
        .order(:available_on, :starts_at)
    end
  end
end
