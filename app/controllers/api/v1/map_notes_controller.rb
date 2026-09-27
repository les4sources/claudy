module Api
  module V1
    # Les notes datées d'une plante ou d'un objet de la carte (epic #348,
    # phase 8) : « 12 mars : bourgeons gelés ». À ne pas confondre avec
    # `NotesController`, les post-it du calendrier.
    #
    # POST /plants/:plant_id/notes, POST /map_features/:map_feature_id/notes,
    # PATCH et DELETE /map_notes/:id (suppression douce).
    class MapNotesController < BaseController
      include MapWriting

      def create
        @map_note = MapNote.new(note_params.merge(subject: map_subject))
        @map_note.save!
        render :show, status: :created
      end

      def update
        @map_note = MapNote.find(params[:id])
        @map_note.update!(note_params)
        render :show
      end

      def destroy
        MapNote.find(params[:id]).soft_delete!(validate: false)
        head :no_content
      end

      private

      def note_params
        params.require(:map_note).permit(:body, :noted_on)
      end
    end
  end
end
