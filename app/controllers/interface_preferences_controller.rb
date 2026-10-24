# Bascule entre l'ancienne et la nouvelle interface (redesign, Michael
# 2026-10-24). Le choix est porté par le COMPTE : la nouvelle interface se
# teste sur les vraies données sans rien imposer aux autres, et l'on revient en
# arrière en un clic.
class InterfacePreferencesController < BaseController
  access_section :everyone

  def update
    current_user.update!(new_interface: ActiveModel::Type::Boolean.new.cast(params[:new_interface]))
    notice = current_user.new_interface? ? "Bienvenue dans la nouvelle interface." : "Tu es revenu·e à l'ancienne interface."
    redirect_to (current_user.new_interface? && current_user.can_read?(:calendar) ? today_path : (access_home_path || root_path)), notice: notice
  end
end
