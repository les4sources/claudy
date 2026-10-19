module Guide
  # « Voir la procédure » (Michael, 2026-10-19) : depuis l'en-tête d'un écran,
  # un rédacteur du Guide y rattache la page qui l'explique (cf.
  # `guide/screen_links/_header`). Le formulaire s'ouvre dans un cadre Turbo
  # paresseux ; l'enregistrement ramène sur l'écran.
  class ScreenLinksController < BaseController
    before_action :require_guide_writer!

    def new
      @link = GuideScreenLink.find_or_initialize_by(screen: params[:screen].to_s)
      @link.path = params[:path].to_s.presence || @link.path
      @link.label = params[:label].to_s.presence || @link.label
      @pages = GuidePage.joins(:chapter).merge(GuideChapter.ordered).order(:position, :id).includes(:chapter)
    end

    def create
      link = GuideScreenLink.find_or_initialize_by(screen: params[:screen].to_s)
      link.assign_attributes(guide_page_id: params[:guide_page_id], path: params[:path].to_s.presence,
                             label: params[:label].to_s.strip.first(160).presence, user: current_user)
      if link.page && link.save
        redirect_to return_path(link), notice: "Cet écran renvoie maintenant à « #{link.page.title} »."
      else
        redirect_to return_path(link), alert: "Le lien vers le Guide n'a pas pu être enregistré."
      end
    end

    def destroy
      link = GuideScreenLink.find(params[:id])
      link.destroy!
      redirect_to return_path(link), notice: "Cet écran ne renvoie plus au Guide."
    end

    private

    # Uniquement une adresse de Claudy (`/…`, jamais `//hôte`).
    def return_path(link)
      path = link.path.to_s
      path.match?(%r{\A/(?!/)}) ? path : guide_root_path
    end
  end
end
