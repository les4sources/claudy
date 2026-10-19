module Guide
  class ChaptersController < BaseController
    before_action :require_guide_writer!
    before_action :set_chapter, only: %i[edit update destroy reorder_pages]

    def new
      @chapter = GuideChapter.new
      breadcrumb "Nouveau chapitre", new_guide_chapter_path
    end

    def create
      @chapter = GuideChapter.new(chapter_params)
      if @chapter.save
        redirect_to guide_root_path(anchor: "chapitre-#{@chapter.id}"), notice: "Le chapitre est créé."
      else
        breadcrumb "Nouveau chapitre", new_guide_chapter_path
        render :new, status: :unprocessable_content
      end
    end

    def edit
      breadcrumb @chapter.title, edit_guide_chapter_path(@chapter)
    end

    def update
      if @chapter.update(chapter_params)
        redirect_to guide_root_path(anchor: "chapitre-#{@chapter.id}"), notice: "Le chapitre est enregistré."
      else
        breadcrumb @chapter.title_was, edit_guide_chapter_path(@chapter)
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      unless @chapter.removable?
        return redirect_to(edit_guide_chapter_path(@chapter),
                           alert: "Ce chapitre a encore des pages : déplace-les ou retire-les d'abord.")
      end

      @chapter.soft_delete!(validate: false)
      redirect_to guide_root_path, notice: "Le chapitre « #{@chapter.title} » est retiré du Guide."
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

    def set_chapter
      @chapter = GuideChapter.find(params[:id].to_i)
    end

    def chapter_params
      params.require(:guide_chapter).permit(:title, :description)
    end
  end
end
