module Guide
  # L'historique d'une page : toutes ses versions, chacune lisible telle
  # qu'elle était, et le retour à l'une d'elles (qui ajoute une version).
  class RevisionsController < BaseController
    before_action :require_guide_writer!, only: :restore
    before_action :set_page

    def index
      @revisions = @page.revisions.includes(user: :human)
      breadcrumb @page.title, guide_page_path(@page)
      breadcrumb "Historique", guide_page_revisions_path(@page)
    end

    def show
      @revision = @page.revisions.find(params[:id])
      @markdown = Guide::Markdown.render(@revision.body)
      @current = @revision.id == @page.revisions.first&.id
      breadcrumb @page.title, guide_page_path(@page)
      breadcrumb "Historique", guide_page_revisions_path(@page)
      breadcrumb "Version #{@revision.number}", guide_page_revision_path(@page, @revision)
    end

    def restore
      revision = @page.revisions.find(params[:id])
      Guide::SavePage.new(@page, user: current_user).restore(revision)
      redirect_to guide_page_path(@page), notice: "La page est revenue à la version #{revision.number}."
    end

    private

    def set_page
      @page = readable_pages.find_by(id: params[:page_id].to_i)
      return if @page
      raise ActiveRecord::RecordNotFound unless GuidePage.exists?(params[:page_id].to_i)

      redirect_to guide_root_path, alert: "Cette page n'est pas ouverte à ton rôle."
    end
  end
end
