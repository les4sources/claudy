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

  private

  def body_must_be_present
    return if body.present? && body.to_plain_text.strip.present?

    errors.add(:body, "ne peut pas être vide")
  end
end
