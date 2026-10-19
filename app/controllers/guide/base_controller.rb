module Guide
  # Le Guide des 4 Sources (Michael, 2026-10-19). Tous les rôles le lisent
  # (`access_section :guide`, en lecture pour tous sauf les Sourciers) ; seuls
  # ceux qui l'ont en écriture ouvrent ses formulaires — y compris en GET, sinon
  # un rôle en lecture verrait un formulaire qu'il ne pourrait pas soumettre.
  class BaseController < ::BaseController
    access_section :guide

    helper_method :guide_writer?

    breadcrumb "Le Guide", :guide_root_path, match: :exact

    private

    # Allume « Guide » dans la barre du haut.
    def set_presenters
      @guide_view = true
    end

    # Jamais un compte restreint à ses activités, même Sourcier sur le papier.
    def guide_writer? = current_user&.guide_writer? || false

    # Les chapitres et les pages que ce compte lit (Michael, 2026-10-19 : chaque
    # chapitre choisit ses rôles, les Sourciers lisent tout).
    def readable_chapters = GuideChapter.readable_by(current_user)

    def readable_pages = GuidePage.readable_by(current_user)

    def require_guide_writer!
      return if guide_writer?

      redirect_to guide_root_path, alert: "Seuls les Sourciers modifient le Guide."
    end
  end
end
