# Paramètres › Accès (Michael, 2026-10-09) : les rôles d'accès de chaque
# compte, cf. `Access`. Un seul écran pour tous les comptes, y compris ceux qui
# n'ont pas de fiche membre (accueil, compta). Réservé aux Sourciers, comme
# toute section non déclarée.
class AccessRolesController < BaseController
  breadcrumb "Accès", :access_roles_path, match: :exact

  def index
    @users = User.includes(:human).order(:email)
    @guide_chapters = GuideChapter.ordered
  end

  # Le tableau « Le Guide, par rôle » : pour chaque chapitre, les rôles qui le
  # lisent. Les Sourciers lisent tout, ils n'y ont pas de colonne.
  def update_guide_chapters
    roles_by_chapter = params.fetch(:chapters, {}).permit!.to_h

    GuideChapter.transaction do
      GuideChapter.where(id: roles_by_chapter.keys).find_each do |chapter|
        chapter.update!(access_roles: Array(roles_by_chapter[chapter.id.to_s]))
      end
    end

    redirect_to access_roles_path(anchor: "guide"), notice: "Les chapitres du Guide ont été enregistrés."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to access_roles_path(anchor: "guide"), alert: e.record.errors.full_messages.to_sentence
  end

  def update
    roles_by_user = params.fetch(:users, {}).permit!.to_h
    saved = false

    User.transaction do
      User.where(id: roles_by_user.keys).find_each do |user|
        user.update!(access_roles: Array(roles_by_user[user.id.to_s]))
      end
      # Ne jamais scier la branche : sans Sourcier, plus personne ne pourrait
      # rendre un accès à qui que ce soit.
      raise ActiveRecord::Rollback unless current_user.reload.sourcier?

      saved = true
    end

    if saved
      redirect_to access_roles_path, notice: "Les accès ont été enregistrés."
    else
      redirect_to access_roles_path, alert: "Vous ne pouvez pas retirer votre propre rôle de Sourcier."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to access_roles_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "access"
    )
    @settings_view = true
  end
end
