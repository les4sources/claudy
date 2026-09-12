module Notifications
  # Notifie les destinataires d'un commentaire (epic #242, décision 4).
  #
  # Destinataires = les auteurs des commentaires PRÉCÉDENTS du même objet
  # (« la conversation continue, tu en es ») + ceux que le modèle déclare
  # (`Commentable#comment_recipients` : le bénéficiaire d'une note de frais, les
  # membres d'un pôle…). Jamais l'auteur lui-même, jamais deux fois la même
  # personne. Pas de mentions `@` dans cet epic.
  #
  # Ne crée rien lui-même : il compose la liste et la passe à `Notify`, seul
  # point de création d'une notification.
  class CommentPosted
    def initialize(comment)
      @comment = comment
    end

    def self.call(comment) = new(comment).call

    def call
      Notify.broadcast(
        recipients: recipients,
        actor: @comment.author,
        kind: "comment",
        title: title,
        body: excerpt,
        url: @comment.target_path,
        notifiable: @comment.commentable
      )
    end

    private

    def recipients
      (previous_authors + declared_recipients).compact.uniq - [@comment.author]
    end

    # `with_deleted` : un commentaire supprimé a quand même mis son auteur dans
    # la conversation. Le retirer du fil ne le retire pas des destinataires.
    def previous_authors
      Comment.with_deleted do
        Comment.where(commentable: @comment.commentable)
               .where.not(id: @comment.id)
               .includes(:author)
               .map(&:author)
      end
    end

    def declared_recipients
      return [] unless @comment.commentable.respond_to?(:comment_recipients)

      Array(@comment.commentable.comment_recipients)
    end

    def title
      "#{@comment.author_label} a commenté #{@comment.commentable_label}"
    end

    # Corps court : le fil complet vit sur la page, l'email n'en donne qu'un
    # aperçu. Coupé sur un mot, jamais au milieu.
    def excerpt
      @comment.body.to_plain_text.to_s.squish.truncate(200, separator: " ")
    end
  end
end
