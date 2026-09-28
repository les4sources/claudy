# Ligne de garde (Twilio) : qui décroche maintenant, qui tient le téléphone les
# prochains jours, l'heure de bascule et le journal des derniers appels. Le
# planning lui-même se modifie toujours depuis le calendrier.
class OnCallController < BaseController
  breadcrumb "Ligne de garde", :on_call_path, match: :exact

  UPCOMING_DAYS = 14
  RECENT_CALLS = 50

  def show
    @resolver = OnCall::Resolver.new
    @handover_hour = OnCall::Config.handover_hour
    @days = (@resolver.duty_date...(@resolver.duty_date + UPCOMING_DAYS)).map do |date|
      OnCall::Resolver.new(duty_date: date)
    end
    @calls = PhoneCall.recent.includes(:on_call_human).limit(RECENT_CALLS)
    human_ids = @calls.flat_map { |call| call.attempts.map { |entry| entry["human_id"] } }.compact.uniq
    @attempt_humans = Human.unscoped.where(id: human_ids).index_by(&:id)
  end

  def update
    hour = Integer(params[:handover_hour].to_s, exception: false)
    if hour && (0..23).cover?(hour)
      Setting.set(OnCall::Config::HANDOVER_HOUR_KEY, hour)
      redirect_to on_call_path, notice: "La garde bascule désormais à #{hour} h."
    else
      redirect_to on_call_path, alert: "Heure de bascule invalide (0 à 23)."
    end
  end

  def phone_holder
    human_role = HumanRole.where(role_id: OnCall::Resolver::WATCHMAN_ROLE_ID).selected.find(params[:human_role_id])
    human_role.make_phone_holder!
    redirect_to on_call_path, notice: "#{human_role.human&.name} tient le téléphone le #{I18n.l(human_role.date, format: '%A %-d %B')}."
  end

  private

  def set_presenters
    @organisation_view = true
  end
end
