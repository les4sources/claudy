class NotesController < BaseController
  before_action :get_note, only: [:edit, :update, :destroy]
  before_action :ensure_frame_response, only: [:new, :edit]

  def new
    @note = Note.new
  end

  def create
    @note = Note.new(note_params)
    respond_to do |format|
      if @note.save
        format.turbo_stream { render turbo_stream: turbo_stream.prepend('notes', partial: 'notes/note', locals: { note: @note }) }
        format.html { redirect_to note_url(@note), notice: "Note was successfully created." }
        format.json { render :show, status: :created, location: @note }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @note.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      if @note.update(note_params)
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@note, partial: "notes/note", locals: { note: @note }) }
        format.html { redirect_to note_url(@note), notice: "Note was successfully updated." }
        format.json { render :show, status: :ok, location: @note }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @note.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @note.destroy
    respond_to do |format|
      format.html { redirect_to notes_url, notice: "Note was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  def get_note
    @note = Note.find(params[:id])
  end

  def ensure_frame_response
    return unless Rails.env.development?
    redirect_to root_path unless turbo_frame_request?
  end

  def note_params
    params.require(:note).permit(:body)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "dashboard"
    )
  end
end
