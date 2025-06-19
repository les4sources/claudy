class WatchmanNotesController < BaseController
  before_action :get_watchman_note, only: [:edit, :update, :destroy]
  before_action :ensure_frame_response, only: [:new, :edit]

  layout "modal"

  def new
    @watchman_note = WatchmanNote.new(date: Date.parse(params[:date]))
  end

  def create
    @watchman_note = WatchmanNote.new(watchman_note_params)
    respond_to do |format|
      if @watchman_note.save
        format.turbo_stream { 
          render turbo_stream: [
            turbo_stream.replace("watchman-notes-#{@watchman_note.date}", 
                               partial: 'watchman_notes/edit', 
                               locals: { date: @watchman_note.date }),
            turbo_stream.update("watchman-notes-message-#{@watchman_note.date}", 
                               partial: 'watchman_notes/message', 
                               locals: { message: "Note enregistrée avec succès", type: :notice, date: @watchman_note.date }),
            turbo_stream.replace("human-roles-#{@watchman_note.date.iso8601}", 
                               partial: 'human_roles/day', 
                               locals: { human_roles: HumanRole.where(date: @watchman_note.date, role_id: 1) })
          ]
        }
        format.html { redirect_to day_details_path(date: @watchman_note.date.strftime("%Y-%m-%d")), notice: "Note de veilleur créée avec succès." }
        format.json { render :show, status: :created, location: @watchman_note }
      else
        format.turbo_stream { 
          render turbo_stream: turbo_stream.update("watchman-notes-message-#{@watchman_note.date}", 
                                                 partial: 'watchman_notes/message', 
                                                 locals: { message: @watchman_note.errors.full_messages.join(", "), type: :error, date: @watchman_note.date })
        }
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @watchman_note.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      if @watchman_note.update(watchman_note_params)
        format.turbo_stream { 
          render turbo_stream: [
            turbo_stream.replace("watchman-notes-#{@watchman_note.date}", 
                               partial: 'watchman_notes/edit', 
                               locals: { date: @watchman_note.date }),
            turbo_stream.update("watchman-notes-message-#{@watchman_note.date}", 
                               partial: 'watchman_notes/message', 
                               locals: { message: "Note mise à jour avec succès", type: :notice, date: @watchman_note.date }),
            turbo_stream.replace("human-roles-#{@watchman_note.date.iso8601}", 
                               partial: 'human_roles/day', 
                               locals: { human_roles: HumanRole.where(date: @watchman_note.date, role_id: 1) }),
          ]
        }
        format.html { redirect_to day_details_path(date: @watchman_note.date.strftime("%Y-%m-%d")), notice: "Note de veilleur mise à jour avec succès." }
        format.json { render :show, status: :ok, location: @watchman_note }
      else
        format.turbo_stream { 
          render turbo_stream: turbo_stream.update("watchman-notes-message-#{@watchman_note.date}", 
                                                 partial: 'watchman_notes/message', 
                                                 locals: { message: @watchman_note.errors.full_messages.join(", "), type: :error, date: @watchman_note.date })
        }
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @watchman_note.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    date = @watchman_note.date
    @watchman_note.destroy
    respond_to do |format|
      format.turbo_stream { 
        render turbo_stream: [
          turbo_stream.replace("watchman-notes-#{date}", 
                             partial: 'watchman_notes/edit', 
                             locals: { date: date }),
          turbo_stream.update("watchman-notes-message-#{date}", 
                             partial: 'watchman_notes/message', 
                             locals: { message: "Note supprimée avec succès", type: :notice, date: date }),
          turbo_stream.replace("human-roles-#{date.iso8601}", 
                             partial: 'human_roles/day', 
                             locals: { human_roles: HumanRole.where(date: date, role_id: 1) }),
        ]
      }
      format.html { redirect_to day_details_path(date: date.strftime("%Y-%m-%d")), notice: "Note de veilleur supprimée avec succès." }
      format.json { head :no_content }
    end
  end

  private

  def get_watchman_note
    @watchman_note = WatchmanNote.find(params[:id])
  end

  def ensure_frame_response
    return unless Rails.env.development?
    redirect_to root_path unless turbo_frame_request?
  end

  def watchman_note_params
    params.require(:watchman_note).permit(:date, :note)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "dashboard"
    )
  end
end
