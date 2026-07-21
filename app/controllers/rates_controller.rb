# Paramètres > Tarifs (issue #124) : édition des montants du barème sans
# redéploiement. La liste est groupée par domaine ; chaque ligne s'édite en
# euros (ou en % pour le taux d'acompte) et est convertie en cents.
class RatesController < BaseController
  before_action :get_rate, only: [:update]

  breadcrumb "Tarifs", :rates_path, match: :exact

  def index
    @grouped_rates = Rate.grouped
  end

  def update
    if @rate.update(amount_cents: submitted_amount_cents)
      Pricing::Rates.reset!
      redirect_to rates_path, notice: "Le tarif « #{@rate.label.presence || @rate.key} » a été mis à jour."
    else
      @grouped_rates = Rate.grouped
      flash.now[:alert] = @rate.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  private

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

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "rates"
    )
    @settings_view = true
  end
end
