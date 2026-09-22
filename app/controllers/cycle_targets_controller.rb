# Les targets d'un membre sur un cycle (epic #330, phase 3).
#
# Trois gestes seulement — ajouter, cocher, supprimer — et chacun renvoie le
# BLOC entier en Turbo Stream plutôt que la seule ligne touchée : l'état vide,
# le compteur d'atteintes et l'ordre changent tous en même temps, et remplacer
# le bloc évite trois flux à tenir cohérents.
class CycleTargetsController < BaseController
  before_action :get_target, only: [:toggle_achieved, :destroy]
  before_action :ensure_open_cycle, only: [:toggle_achieved, :destroy]

  def create
    @human = Human.find(params[:human_id])
    @cycle = Cycle.find(params[:cycle_id])

    return refuse_closed_cycle unless @cycle.open?

    target = @cycle.cycle_targets.new(human: @human, label: params[:label])
    # Un libellé vide n'est pas une erreur à afficher : c'est un Entrée dans un
    # champ vide. On renvoie le bloc inchangé plutôt qu'un message.
    target.save if target.label.present?

    respond_with_block
  end

  def toggle_achieved
    @target.toggle_achieved!
    respond_with_block
  end

  def destroy
    @target.destroy
    respond_with_block
  end

  private

  def get_target
    @target = CycleTarget.find(params[:id])
    @human = @target.human
    @cycle = @target.cycle
  end

  def ensure_open_cycle
    return if @cycle.open?

    refuse_closed_cycle
  end

  def refuse_closed_cycle
    message = "Ce cycle est clos : ses targets ne se modifient plus."
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "flash_toasts",
          partial: "cycle_actions/error_toast",
          locals: { message: message, cycle: @cycle }
        )
      end
      format.html { redirect_to member_path, alert: message }
    end
  end

  def respond_with_block
    @targets = CycleTarget.where(human: @human, cycle: @cycle).ordered
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "cycle_targets_block",
          partial: "cycle_targets/block",
          locals: { targets: @targets, human: @human, cycle: @cycle, readonly: false }
        )
      end
      format.html { redirect_to member_path }
    end
  end

  def member_path = organisation_member_path(@human.id, cycle_id: @cycle&.id)

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "organisation")
    @organisation_view = true
  end
end
