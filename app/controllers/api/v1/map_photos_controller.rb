module Api
  module V1
    # Les photos d'une plante ou d'un objet de la carte (epic #348, phase 8).
    #
    # POST multipart (`photos[]`, un ou plusieurs fichiers) : la réponse liste les
    # pièces jointes CRÉÉES, `{ photos: [{ id, filename, url }] }`. Un fichier qui
    # n'est pas une photo acceptée (JPEG, PNG, HEIC si le serveur sait la
    # convertir) refuse tout l'envoi en 422, sans rien attacher.
    class MapPhotosController < BaseController
      include MapWriting

      def create
        files = Array(params[:photos]).select { |file| file.respond_to?(:original_filename) }
        return render_errors("photos[] attend au moins un fichier (multipart/form-data)") if files.empty?

        subject = map_subject
        existing = subject.photos_attachments.pluck(:id)
        return render_invalid(subject) unless subject.photos.attach(files)

        @photos = subject.photos_attachments.where.not(id: existing).includes(:blob).order(:id)
        render :create, status: :created
      end

      def destroy
        map_subject.photos_attachments.find(params[:id]).purge
        head :no_content
      end
    end
  end
end
