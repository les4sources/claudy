# Rattachement d'une Pizza Party privée de Tranches de Vie à un séjour
# (issue #339), depuis la fiche séjour.
#
# Le rattachement est MANUEL et à sens unique : on lit l'API de Tranches de Vie,
# on n'y écrit jamais. Chaque mutation rejoue `recompute_aggregates!` puis
# `set_payment_status`. Le bloc Pizza Party vit dans la colonne de droite
# (frame `stay_<id>_extras`), les montants à gauche (frame `stay_<id>_payments`) :
# la réponse Turbo Stream remplace les deux, comme pour les activités. Hors
# Turbo, on redirige vers `stay_path`.
class StayPartyReservationsController < BaseController
  before_action :set_stay

  # Les candidates : les parties privées PAYÉES tenues autour des dates du
  # séjour. Rendu dans un turbo-frame, pas de page pleine.
  def index
    @client = TranchesDeVie::Client.new
    @candidates = []
    @error = nil

    if @client.configured?
      begin
        @candidates = sorted_candidates(@client.private_parties(held_on_from: window_start, held_on_to: window_end))
      rescue TranchesDeVie::Client::Error => e
        @error = e.message
      end
    else
      @error = NOT_CONFIGURED
    end

    render partial: "stays/party_candidates",
           locals: { stay: @stay, candidates: @candidates, error: @error },
           layout: false
  end

  def create
    service = TranchesDeVie::AttachPartyReservation.new(stay: @stay)

    if service.run(params.require(:external_id))
      respond_with_panels(notice: "Pizza Party rattachée au séjour.")
    else
      respond_with_panels(alert: service.error_message(default: "Rattachement impossible."))
    end
  end

  def destroy
    reservation = @stay.party_reservations.find(params[:id])
    service = TranchesDeVie::DetachPartyReservation.new(party_reservation: reservation)

    if service.run
      respond_with_panels(notice: "Pizza Party détachée du séjour.")
    else
      respond_with_panels(alert: service.error_message(default: "Détachement impossible."))
    end
  end

  # Synchronisation à la demande des parties de CE séjour : la compta n'a pas à
  # attendre le passage quotidien pour voir un remboursement arriver.
  def sync
    service = TranchesDeVie::SyncPartyReservations.for_stay(@stay)

    if service.run
      respond_with_panels(notice: sync_notice(service))
    else
      respond_with_panels(alert: service.error_message(default: "Synchronisation impossible."))
    end
  end

  private

  NOT_CONFIGURED = "Connexion à Tranches de Vie non configurée".freeze

  def set_stay
    @stay = Stay.find(params[:stay_id])
  end

  def respond_with_panels(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        @stay = Stay.find(@stay.id).decorate
        render turbo_stream: [
          turbo_stream.replace("stay_#{@stay.id}_extras") do
            render_to_string(partial: "stays/extras_panel", formats: [:html], locals: { notice: notice, alert: alert })
          end,
          turbo_stream.replace("stay_#{@stay.id}_payments") do
            render_to_string(partial: "stays/payments_panel", formats: [:html])
          end
        ]
      end
      format.html { redirect_to stay_path(@stay), notice: notice, alert: alert }
    end
  end

  # Fenêtre de recherche : les dates du séjour à un jour près (une party se tient
  # souvent la veille de l'arrivée ou le lendemain du départ). Séjour sans dates :
  # un mois autour d'aujourd'hui, faute de mieux.
  def window_start
    @stay.arrival_date.present? ? @stay.arrival_date - 1 : Date.current - 30
  end

  def window_end
    @stay.departure_date.present? ? @stay.departure_date + 1 : Date.current + 30
  end

  # Les candidates du MÊME CLIENT d'abord : c'est presque toujours la bonne, et
  # la faire chercher dans une liste de dates est du travail pour rien.
  def sorted_candidates(orders)
    mappers = orders.map { |order| TranchesDeVie::OrderMapper.new(order) }
    mappers.sort_by { |m| [same_customer?(m) ? 0 : 1, m.attributes[:held_on].to_s] }
  end

  def same_customer?(mapper)
    customer = @stay.customer
    return false unless customer

    emails = [customer.try(:email)].compact.map { |e| e.to_s.downcase }
    phones = [customer.try(:phone), customer.try(:phone_e164)].compact.map { |p| normalise_phone(p) }.reject(&:blank?)

    (mapper.customer_email.present? && emails.include?(mapper.customer_email)) ||
      (mapper.customer_phone.present? && phones.include?(normalise_phone(mapper.customer_phone)))
  end

  def normalise_phone(value)
    value.to_s.gsub(/\D/, "").sub(/\A0+/, "")
  end

  def sync_notice(service)
    return "Aucune Pizza Party active à synchroniser." if service.checked.zero?
    return "#{service.checked} Pizza Party vérifiée#{'s' if service.checked > 1} : aucun changement." if service.changed.zero?

    "#{service.changed} Pizza Party mise#{'s' if service.changed > 1} à jour depuis Tranches de Vie."
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "accounting",
      active_secondary: "payments"
    )
    @home_view = true
  end
end
