module Notifications
  # Les notifications d'un fil de commentaires de la carte (epic #348,
  # phase 11). Compose les destinataires et passe la main à `Notify`, seul point
  # de création d'une notification. Le lien ouvre la carte centrée sur le point,
  # fiche ouverte : `/map?feature=<id>`.
  module MapThread
    module_function

    # Une réponse : tous les participants du fil, sauf son auteur.
    def replied(reply)
      Notify.broadcast(
        recipients: reply.participants.to_a - [reply.author],
        actor: reply.author,
        kind: "map_comment",
        title: "#{reply.author.display_name} a répondu à un commentaire de la carte",
        body: excerpt(reply.body),
        url: url_for(reply),
        notifiable: reply.root
      )
    end

    # Une résolution : l'auteur du premier message (`Notify` ignore celui qui
    # résout son propre fil).
    def resolved(root, by:)
      Notify.new(
        recipient: root.author,
        actor: by,
        kind: "map_comment_resolved",
        title: "#{by&.display_name || 'Quelqu’un'} a marqué votre commentaire de la carte comme résolu",
        body: excerpt(root.body),
        url: url_for(root),
        notifiable: root
      ).run
    end

    def url_for(comment)
      Rails.application.routes.url_helpers.map_path(feature: comment.map_feature_id)
    end

    def excerpt(body) = body.to_s.squish.truncate(200, separator: " ")
  end
end
