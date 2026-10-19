module Guide
  # Crée ou modifie une page du Guide. Le seul chemin d'écriture, pour l'écran
  # comme pour le serveur MCP : chaque changement du titre ou du contenu écrit
  # une révision signée de son auteur, et met à jour le « dernier éditeur » de
  # la page.
  #
  #   Guide::SavePage.new(page, user: current_user).call(title: "…", body: "…")
  class SavePage
    # Une image téléversée par l'éditeur, dans le Markdown :
    # ![légende](/rails/active_storage/blobs/redirect/<signed_id>/photo.jpg)
    IMAGE_PATH = %r{/rails/active_storage/blobs/(?:redirect|proxy)/([^/\s)]+)/}

    attr_reader :page

    def initialize(page, user:, source: "web")
      @page = page
      @user = user
      @source = source
    end

    # `attributes` : `title`, `body`, `guide_chapter_id` (tous facultatifs en
    # modification), `summary` (ce qui a changé, pour l'historique). Rend
    # `true`, ou `false` avec les erreurs sur la page.
    def call(attributes)
      attributes = attributes.to_h.symbolize_keys
      page.assign_attributes(attributes.slice(:title, :body, :guide_chapter_id).compact)
      page.body = page.body.to_s.gsub("\r\n", "\n").rstrip
      move_to_end_of_chapter if page.persisted? && page.guide_chapter_id_changed?
      content_changed = page.new_record? || page.title_changed? || page.body_changed?

      ApplicationRecord.transaction do
        if content_changed
          page.last_editor = @user
          page.last_edited_at = Time.current
        end
        page.save!
        if content_changed
          page.revisions.create!(user: @user, title: page.title, body: page.body, source: @source,
                                 summary: attributes[:summary].to_s.strip.first(250).presence)
        end
        attach_images
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Revient à une version : la page reprend son titre et son contenu, et
    # l'historique gagne une révision — rien n'est effacé.
    def restore(revision)
      call(title: revision.title, body: revision.body, summary: "Retour à la version #{revision.number}")
    end

    private

    def move_to_end_of_chapter
      page.position = (GuidePage.where(guide_chapter_id: page.guide_chapter_id).maximum(:position) || 0) + 1
    end

    def attach_images
      attached = page.images.blobs.pluck(:id)
      page.body.scan(IMAGE_PATH).flatten.uniq.each do |signed_id|
        blob = ActiveStorage::Blob.find_signed(signed_id)
        next if blob.nil? || attached.include?(blob.id)

        page.images.attach(blob)
        attached << blob.id
      end
    end
  end
end
