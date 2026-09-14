# Un commentaire posé sur n'importe quel objet commentable (epic #242,
# décision 1). Le corps est riche (ActionText), l'auteur est un `User`, et la
# suppression est douce : un fil de discussion garde sa cohérence même quand une
# ligne disparaît de l'affichage.
# == Schema Information
#
# Table name: comments
#
#  id               :bigint           not null, primary key
#  commentable_type :string           not null
#  deleted_at       :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  author_id        :bigint           not null
#  commentable_id   :bigint           not null
#
# Indexes
#
#  index_comments_on_author_id                   (author_id)
#  index_comments_on_commentable                 (commentable_type,commentable_id)
#  index_comments_on_commentable_and_created_at  (commentable_type,commentable_id,created_at)
#  index_comments_on_deleted_at                  (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => users.id)
#
class Comment < ApplicationRecord
  # Liste blanche des types commentables. Le contrôleur résout `commentable`
  # PAR CETTE LISTE, jamais par un `constantize` libre : un paramètre de type
  # arbitraire ne doit pas pouvoir instancier une classe au hasard.
  #
  # Les phases suivantes de l'epic l'étendent (`ExpenseReport`,
  # `PurchaseInvoice`, `Event`, `Decision`, `ExperienceBooking`).
  COMMENTABLE_TYPES = %w[Gathering Stay].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"

  has_rich_text :body

  validates :commentable_type, inclusion: { in: COMMENTABLE_TYPES }
  validate :body_must_be_present

  scope :chronological, -> { order(created_at: :asc) }

  # Identifiant DOM du fil d'un objet — le même côté composant et côté Turbo
  # Stream, sinon la réponse ne remplace rien.
  def self.thread_dom_id(commentable)
    "comments-thread-#{commentable.class.name.underscore}-#{commentable.id}"
  end

  # Modifiable et supprimable par son auteur ; un admin global (compte sans
  # `human`, cf. `User#global_admin?`) peut intervenir sur tout le fil.
  def editable_by?(user)
    return false if user.blank?

    author_id == user.id || user.global_admin?
  end

  # Le membre d'équipe derrière l'auteur, quand il y en a un — c'est lui qui
  # porte la photo affichée dans le fil.
  def author_human
    author&.linked_human
  end

  def author_label
    author_human&.name.presence || author&.email.to_s
  end

  # Ancre DOM d'un commentaire dans son fil — l'adresse vers laquelle pointe la
  # notification (epic #242, phase 2).
  def dom_anchor = "comment-#{id}"

  # Adresse de la page de l'objet, ancrée sur ce commentaire. Résolue par
  # `polymorphic_path` sur un type de la LISTE BLANCHE : aucun nom de classe
  # venu d'ailleurs n'arrive jusqu'ici.
  def target_path
    Rails.application.routes.url_helpers.polymorphic_path(commentable, anchor: dom_anchor)
  rescue NoMethodError, ActionController::UrlGenerationError
    # Un commentable sans route nommée ne doit pas empêcher le commentaire
    # d'exister : la notification pointera sur l'accueil plutôt que d'exploser.
    "/"
  end

  # « le séjour de Martin », « le rassemblement du 3 mars » — ce que la
  # notification met dans son titre. Repli sur le nom du modèle quand l'objet
  # n'a rien de plus parlant à offrir.
  def commentable_label
    return commentable.comment_label if commentable.respond_to?(:comment_label)

    commentable_type.underscore.humanize.downcase
  end

  private

  def body_must_be_present
    return if body.present? && body.to_plain_text.strip.present?

    errors.add(:body, "ne peut pas être vide")
  end
end
