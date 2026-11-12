module Documents
  # Un fichier : son aperçu (`show`), l'envoi (`create`), renommer (`update`)
  # et ses trois sorties, toutes derrière la section d'accès — jamais une
  # adresse publique d'Active Storage :
  # - `download` : le fichier, sous son nom dans Claudy ;
  # - `raw` : affiché dans la page (PDF, photo, vidéo, son) ;
  # - `thumb` : la vignette d'une photo.
  class FilesController < BaseController
    before_action :require_documents_writer!, only: %i[create update]
    before_action :set_file, only: %i[show update download raw thumb]

    TEXT_PREVIEW_BYTES = 200.kilobytes

    def show
      return redirect_to(documents_trash_path, alert: "Ce fichier est à la corbeille.") if @file.trashed?

      @ancestors = @file.folder ? @file.folder.ancestors + [@file.folder] : []
      @siblings = DocumentFile.kept.where(document_folder_id: @file.document_folder_id).order(Arel.sql(AccentFolding.sql("name"))).pluck(:id, :name)
      position = @siblings.index { |id, _| id == @file.id }
      @previous_id = @siblings[position - 1]&.first if position&.positive?
      @next_id = @siblings[position + 1]&.first if position
      @text_preview = text_preview if @file.kind == :text
    end

    def create
      folder = target_folder(params[:folder_id])
      result = Documents::Upload.new(folder: folder, user: current_user).call(params[:files])
      created = result.files.size
      notice = "#{plural(created, 'fichier envoyé', 'fichiers envoyés')} dans #{folder ? "« #{folder.name} »" : 'Documents'}." if created.positive?
      alert = result.errors.join(" · ").presence
      alert ||= "Choisis au moins un fichier." if created.zero?
      # Le bandeau rend le flash en HTML : noms échappés.
      flash[:notice] = ERB::Util.html_escape(notice) if notice
      flash[:alert] = ERB::Util.html_escape(alert) if alert
      fresh = result.files.map(&:id)
      respond_to do |format|
        format.json { render json: { ok: result.errors.empty?, created: created, ids: fresh, errors: result.errors }, status: (created.positive? ? :created : :unprocessable_content) }
        format.html do
          location = folder ? documents_folder_path(folder, nouveaux: fresh.join(",").presence) : documents_path(nouveaux: fresh.join(",").presence)
          redirect_to location, status: :see_other
        end
      end
    rescue ActiveRecord::RecordNotFound
      respond_refused("Ce dossier n’existe plus.", location: documents_path)
    end

    # Renommer : l'extension d'origine reste, même si on l'efface en tapant.
    def update
      old = @file.name
      name = params.dig(:file, :name).to_s.squish
      ext = File.extname(old)
      name = "#{name}#{ext}" if name.present? && ext.present? && !name.downcase.end_with?(ext.downcase)
      if @file.update(name: name)
        respond_done(old == @file.name ? "Le nom n’a pas changé." : "« #{old} » s’appelle maintenant « #{@file.name} ».", location: back_location(folder_location(@file.folder)))
      else
        respond_refused(@file.errors.full_messages.to_sentence, location: back_location)
      end
    end

    def download
      serve(disposition: "attachment")
    end

    def raw
      media = @file.inline? || @file.content_type.start_with?("video/", "audio/")
      serve(disposition: media ? "inline" : "attachment")
    end

    def thumb
      return head(:not_found) unless @file.thumbnail?

      variant = @file.file.variant(resize_to_limit: [480, 480], format: :webp).processed
      serve_blob(variant.image.blob, disposition: "inline", filename: "#{File.basename(@file.name, '.*')}.webp")
    rescue StandardError => e
      Rails.logger.warn("[documents] vignette impossible pour ##{@file.id} : #{e.class} #{e.message}")
      serve(disposition: "inline")
    end

    private

    def set_file
      @file = DocumentFile.find(params[:id].to_i)
    end

    def serve(disposition:)
      serve_blob(@file.file.blob, disposition: disposition, filename: @file.name)
    end

    # Sur le disque du serveur (le service de Claudy), `send_file` lit par
    # morceaux sans tout charger en mémoire ; ailleurs, on lit le blob.
    def serve_blob(blob, disposition:, filename:)
      type = blob.content_type.presence || "application/octet-stream"
      response.headers["Cache-Control"] = "private, max-age=300"
      service = blob.service
      if service.respond_to?(:path_for)
        send_file service.path_for(blob.key), type: type, disposition: disposition, filename: filename
      else
        send_data blob.download, type: type, disposition: disposition, filename: filename
      end
    end

    def text_preview
      data = @file.file.blob.service.respond_to?(:path_for) ? File.binread(@file.file.blob.service.path_for(@file.file.blob.key), TEXT_PREVIEW_BYTES) : @file.file.download.first(TEXT_PREVIEW_BYTES)
      text = data.to_s.dup.force_encoding("UTF-8")
      text = text.encode("UTF-8", "Windows-1252", invalid: :replace, undef: :replace) unless text.valid_encoding?
      text.scrub
    rescue StandardError
      nil
    end
  end
end
