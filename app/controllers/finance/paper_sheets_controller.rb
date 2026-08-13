module Finance
  # Fiches papier et écran d'encodage matriciel (issue #158).
  class PaperSheetsController < Finance::BaseController
    before_action :get_sheet, only: [:show, :edit, :update, :destroy, :encode, :save_encoding]

    breadcrumb "Fiches papier", :finance_paper_sheets_path, match: :exact

    def index
      @sheets = PaperSheet.recent_first.includes(:account_entries)
    end

    def show
      redirect_to encode_finance_paper_sheet_path(@sheet)
    end

    def new
      @sheet = PaperSheet.new(period_month: Date.current.beginning_of_month, channel: "bar")
    end

    def create
      @sheet = PaperSheet.new(sheet_params)

      if @sheet.save
        redirect_to encode_finance_paper_sheet_path(@sheet), notice: "Fiche créée — à toi de l'encoder."
      else
        flash.now[:alert] = @sheet.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @sheet.update(sheet_params)
        redirect_to encode_finance_paper_sheet_path(@sheet), notice: "Fiche mise à jour."
      else
        flash.now[:alert] = @sheet.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @sheet.soft_delete!(validate: false)
      redirect_to finance_paper_sheets_path, notice: "Fiche supprimée."
    end

    # La matrice : une ligne par article du canal, une colonne par compte actif.
    def encode
      breadcrumb "Encodage", encode_finance_paper_sheet_path(@sheet), match: :exact

      @items = @sheet.catalog_items.to_a
      @accounts = MemberAccount.ordered.where(active: true).to_a
      @entries = @sheet.account_entries
                       .unscoped
                       .where(paper_sheet_id: @sheet.id)
                       .index_by { |entry| [entry.member_account_id, entry.catalog_item_id] }
    end

    def save_encoding
      report = Finance::EncodePaperSheet.new(
        sheet: @sheet,
        cells: params[:cells]&.to_unsafe_h,
        entry_mode: params[:entry_mode],
        whodunnit: current_user&.email
      ).run!

      redirect_to encode_finance_paper_sheet_path(@sheet), notice: "Fiche enregistrée : #{report.summary}."
    end

    private

    def get_sheet
      @sheet = PaperSheet.find(params[:id])
    end

    def sheet_params
      params.require(:paper_sheet).permit(:period_month, :channel, :status, :entry_mode,
                                          :member_account_id, :notes, :photo)
    end

    def finance_secondary = "paper_sheets"
  end
end
