module Guide
  class PagesController < BaseController
    before_action :require_guide_writer!, except: %i[index show]
    before_action :set_page, only: %i[show edit update destroy]

    def index
      @query = params[:q].to_s.strip
      @chapters = GuideChapter.ordered.includes(pages: { last_editor: :human })
      @results = GuidePage.search(@query).includes(:chapter, last_editor: :human).order(:title) if @query.present?
      @recent_pages = GuidePage.where.not(last_edited_at: nil).includes(:chapter, last_editor: :human)
                               .order(last_edited_at: :desc).limit(5)
    end

    def show
      @markdown = Guide::Markdown.render(@page.body, new_page_links: guide_writer?)
      @chapters = GuideChapter.ordered.includes(:pages)
      siblings = @chapters.flat_map(&:pages)
      index = siblings.index(@page)
      @previous_page = siblings[index - 1] if index&.positive?
      @next_page = siblings[index + 1] if index
      @contributors = @page.contributors
      @backlinks = @page.backlinks
      @screen_links = @page.screen_links.to_a
      breadcrumb @page.chapter.title, guide_root_path(anchor: "chapitre-#{@page.chapter.id}")
      breadcrumb @page.title, guide_page_path(@page)
    end

    def new
      chapter = GuideChapter.find_by(id: params[:chapter_id]) || GuideChapter.ordered.first
      return redirect_to(new_guide_chapter_path, alert: "Crée d'abord un chapitre.") if chapter.nil?

      # `title` : depuis un lien `[[Titre]]` vers une page qui n'existe pas encore.
      @page = GuidePage.new(chapter: chapter, title: params[:title].to_s.squish.first(160).presence)
      breadcrumb "Nouvelle page", new_guide_page_path
    end

    def create
      @page = GuidePage.new
      if Guide::SavePage.new(@page, user: current_user).call(page_params)
        redirect_to guide_page_path(@page), notice: "La page est publiée dans le Guide."
      else
        breadcrumb "Nouvelle page", new_guide_page_path
        render :new, status: :unprocessable_content
      end
    end

    def edit
      breadcrumb @page.title, guide_page_path(@page)
      breadcrumb "Modifier", edit_guide_page_path(@page)
    end

    def update
      if Guide::SavePage.new(@page, user: current_user).call(page_params)
        redirect_to guide_page_path(@page), notice: "La page est enregistrée."
      else
        breadcrumb @page.title_was, guide_page_path(@page)
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @page.soft_delete!(validate: false)
      redirect_to guide_root_path, notice: "La page « #{@page.title} » est retirée du Guide."
    end

    private

    def set_page
      @page = GuidePage.find(params[:id].to_i)
    end

    def page_params
      params.require(:guide_page).permit(:title, :body, :guide_chapter_id, :summary)
    end
  end
end
