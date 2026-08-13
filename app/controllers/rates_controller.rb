# Paramètres > Tarifs (issue #124) : édition des montants du barème sans
# redéploiement. La liste est groupée par domaine ; chaque ligne s'édite en
# euros (ou en % pour le taux d'acompte) et est convertie en cents.
class RatesController < BaseController
  before_action :get_rate, only: [:update]

  breadcrumb "Tarifs", :rates_path, match: :exact

  def index
    @grouped_rates = Rate.grouped
  end

  # Depuis #156, l'édition passe par `Rates::UpdateAmount` : elle ouvre une
  # version datée et ne touche au montant courant que si la date saisie couvre
  # aujourd'hui. Sans date saisie, le comportement est celui d'avant — le prix
  # change tout de suite.
  def update
    service = Rates::UpdateAmount.new(rate: @rate)

    if service.run(amount_cents: submitted_amount_cents, active_from: submitted_active_from)
      redirect_to rates_path, notice: update_notice(service.version)
    else
      @grouped_rates = Rate.grouped
      flash.now[:alert] = update_error_message(service)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def rate_label = @rate.label.presence || @rate.key

  def update_notice(version)
    return "Le tarif « #{rate_label} » a été mis à jour." if version.nil? || version.covers?(Date.current)

    "Le tarif « #{rate_label} » changera le #{I18n.l(version.active_from, format: :long)} " \
      "— la valeur actuelle est inchangée."
  end

  def update_error_message(service)
    errors = service.version&.errors&.full_messages
    errors.presence&.to_sentence || service.error_message(default: "Le tarif n'a pas pu être mis à jour.")
  end

  def get_rate
    @rate = Rate.find(params[:id])
  end

  # Montant saisi : euros (virgule tolérée) pour les tarifs, % pour un taux.
  # Une saisie vide ou non numérique retombe sur -1 pour déclencher la
  # validation « ≥ 0 » plutôt que de passer silencieusement à zéro.
  def submitted_amount_cents
    raw = params.dig(:rate, :amount).to_s.strip.tr(",", ".")
    return -1 unless raw.match?(/\A-?\d+(\.\d+)?\z/)

    @rate.percent? ? raw.to_f.round : (raw.to_f * 100).round
  end

  # « À partir du », facultatif : vide = aujourd'hui, donc le comportement
  # historique de l'écran.
  def submitted_active_from
    params.dig(:rate, :active_from).presence
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "rates"
    )
    @settings_view = true
  end
end
