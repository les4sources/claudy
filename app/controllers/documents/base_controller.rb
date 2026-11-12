module Documents
  # Les Documents du collectif (Michael, 2026-11-12). Section d'accès
  # `:documents` : Sourciers et Administratif, en écriture (`Access::GRANTS`).
  # Un rôle qui n'aurait la section qu'en lecture consulte et télécharge, mais
  # ne voit aucun geste d'écriture (`documents_writer?`), et `AccessControl` lui
  # refuse toute requête autre que GET.
  class BaseController < ::BaseController
    access_section :documents

    helper_method :documents_writer?, :documents_tree

    private

    # Allume « Documents » dans les deux barres de navigation.
    def set_presenters
      @documents_view = true
    end

    def documents_writer? = section_writable?(:documents)

    def documents_tree = @documents_tree ||= Documents::Tree.new

    def require_documents_writer!
      return if documents_writer?

      redirect_to documents_path, alert: AccessControl::READ_ONLY
    end

    # Le dossier d'arrivée d'un geste : `""` ou absent = la racine.
    def target_folder(param)
      id = param.to_s.to_i
      id.positive? ? DocumentFolder.kept.find(id) : nil
    end

    def folder_location(folder) = folder ? documents_folder_path(folder) : documents_path

    # Les éléments d'un geste sur une sélection : `folder_ids[]` et `file_ids[]`.
    def selected(scope_folders, scope_files)
      [scope_folders.where(id: ids_param(:folder_ids)).to_a, scope_files.where(id: ids_param(:file_ids)).to_a]
    end

    def ids_param(key) = Array(params[key]).flat_map { |v| v.to_s.split(",") }.map(&:to_i).select(&:positive?).uniq

    # Une réponse pour le glisser-déposer (fetch, JSON) comme pour un
    # formulaire : le message part dans le flash de la page qu'on recharge.
    # Le bandeau du layout rend le flash TEL QUEL (HTML) : un nom de fichier
    # y passe échappé, sinon « <img onerror=…>.pdf » s'exécuterait.
    def respond_done(message, location:)
      flash[:notice] = ERB::Util.html_escape(message)
      respond_to do |format|
        format.json { render json: { ok: true, message: message, location: location } }
        format.html { redirect_to location, status: :see_other }
      end
    end

    def respond_refused(message, location:)
      respond_to do |format|
        format.json { render json: { ok: false, error: message }, status: :unprocessable_content }
        format.html { redirect_to location, alert: ERB::Util.html_escape(message), status: :see_other }
      end
    end

    def back_location(fallback = documents_path)
      referer = request.referer.to_s
      referer.start_with?(request.base_url + "/documents") ? referer : fallback
    end

    def plural(count, one, many = "#{one}s") = "#{count} #{count > 1 ? many : one}"
  end
end
