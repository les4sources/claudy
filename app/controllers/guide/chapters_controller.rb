module Guide
  class ChaptersController < BaseController
    before_action :require_guide_writer!, except: :show
    before_action :set_chapter, only: %i[edit update destroy reorder_pages]

    # Une section du Guide (Michael, 2026-11-12) : tous ses chapitres à lire
    # d'affilée, et à droite un menu pour sauter de l'un à l'autre ou revenir
    # à toutes les sections. Nouvelle interface seulement : l'ancienne garde
    # son sommaire d'un seul tenant.
    def show
      @chapter = readable_chapters.find_by(id: params[:id].to_i)
      if @chapter.nil?
        raise ActiveRecord::RecordNotFound unless GuideChapter.exists?(params[:id].to_i)

        return redirect_to(guide_root_path, alert: "Cette section n'est pas ouverte à ton rôle.")
      end
      return redirect_to(guide_root_path(anchor: "chapitre-#{@chapter.id}")) unless current_user.new_interface?

      @pages = @chapter.pages.includes(last_editor: :human).to_a
      readable = readable_pages
      @renders = @pages.to_h do |page|
        [page.id, Guide::Markdown.render(page.body, new_page_links: guide_writer?, pages: readable)]
      end
      @chapters = readable_chapters.ordered.to_a
      breadcrumb @chapter.title, guide_chapter_path(@chapter)
    end

    def new
      @chapter = GuideChapter.new
      breadcrumb "Nouvelle section", new_guide_chapter_path
    end

    def create
      @chapter = GuideChapter.new(chapter_params)
      if @chapter.save
        redirect_to chapter_return_path, notice: "La section est créée."
      else
        breadcrumb "Nouvelle section", new_guide_chapter_path
        render :new, status: :unprocessable_content
      end
    end

    def edit
      breadcrumb @chapter.title, edit_guide_chapter_path(@chapter)
    end

    def update
      if @chapter.update(chapter_params)
        redirect_to chapter_return_path, notice: "La section est enregistrée."
      else
        breadcrumb @chapter.title_was, edit_guide_chapter_path(@chapter)
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      unless @chapter.removable?
        return redirect_to(edit_guide_chapter_path(@chapter),
                           alert: "Cette section a encore des chapitres : déplace-les ou retire-les d'abord.")
      end

      @chapter.soft_delete!(validate: false)
      redirect_to guide_root_path, notice: "La section « #{@chapter.title} » est retirée du Guide."
    end

    # Glisser-déposer des chapitres dans le sommaire.
    def reorder
      GuideChapter.reorder!(params[:ids])
      head :no_content
    end

    # Glisser-déposer des pages d'un chapitre, y compris celles qui y arrivent
    # depuis un autre chapitre.
    def reorder_pages
      GuidePage.reorder!(@chapter, params[:ids])
      head :no_content
    end

    private

    # Après l'enregistrement : la section elle-même dans la nouvelle interface,
    # sa place dans le sommaire dans l'ancienne.
    def chapter_return_path
      current_user.new_interface? ? guide_chapter_path(@chapter) : guide_root_path(anchor: "chapitre-#{@chapter.id}")
    end

    def set_chapter
      @chapter = GuideChapter.find(params[:id].to_i)
    end

    def chapter_params
      params.require(:guide_chapter).permit(:title, :description, access_roles: [])
    end
  end
end
