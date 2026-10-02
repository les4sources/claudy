# Un message d'un fil de commentaires sur la carte du domaine (epic #348,
# phase 11) : « la clôture est cassée ici », « on déplace le compost ? ».
#
# Un point de commentaire (`MapFeature`, `feature_kind` `comment`) porte UN
# fil : un message racine (`parent_id` nul) et ses réponses. Le fil est plat —
# une réponse pointe toujours vers la racine, jamais vers une autre réponse —
# et c'est la racine qui dit si le fil est résolu (`resolved_at`).
#
# Supprimer = soft-delete (PaperTrail garde la trace). Supprimer la racine
# supprime le fil entier ET son point : un point sans premier message n'a plus
# rien à dire (`#remove!`).
class MapComment < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :map_feature
  belongs_to :parent, class_name: "MapComment", optional: true, inverse_of: :replies
  belongs_to :author, class_name: "User"
  # Pas de `dependent:` : les réponses sont soft-deletées par `#remove!`.
  has_many :replies, class_name: "MapComment", foreign_key: :parent_id, inverse_of: :parent

  before_validation { self.body = body.to_s.strip.presence }

  validates :body, presence: true
  validate :parent_is_root_of_same_point
  validate :single_root_per_point
  validate :resolution_only_on_root

  scope :roots, -> { where(parent_id: nil) }
  # La racine d'abord, puis les réponses dans l'ordre où elles sont arrivées.
  scope :chronological, -> { order(Arel.sql("map_comments.parent_id IS NOT NULL"), :created_at, :id) }

  def root? = parent_id.nil?

  def root = root? ? self : parent

  # Le fil complet : la racine et ses réponses vivantes, dans l'ordre.
  def thread
    MapComment.where(id: root.id).or(MapComment.where(parent_id: root.id)).chronological.includes(:author)
  end

  # Tous ceux qui ont écrit dans le fil, y compris un message supprimé depuis :
  # retirer son message ne retire pas de la conversation (même règle que
  # `Notifications::CommentPosted`).
  def participants
    author_ids = MapComment.with_deleted do
      MapComment.where(id: root.id).or(MapComment.where(parent_id: root.id)).distinct.pluck(:author_id)
    end
    User.where(id: author_ids).order(:id)
  end

  def resolved? = root.resolved_at.present?

  # Une réponse dans le fil. Prévient les participants (sauf l'auteur) : c'est
  # ici, et pas dans le contrôleur, pour que toute réponse suive la même règle.
  def reply!(author:, body:)
    reply = root.replies.create!(map_feature: map_feature, author: author, body: body)
    Notifications::MapThread.replied(reply)
    reply
  end

  # Résout le fil (sur la racine, d'où qu'on l'appelle) et prévient l'auteur de
  # la racine, sauf s'il résout lui-même. Idempotent : un fil déjà résolu ne
  # renvoie pas de notification.
  def resolve!(by:)
    return false if resolved?

    root.update!(resolved_at: Time.current)
    Notifications::MapThread.resolved(root, by: by)
    true
  end

  def reopen!
    root.update!(resolved_at: nil)
  end

  def removable_by?(user) = user.present? && author_id == user.id

  # Une réponse disparaît seule ; la racine emporte le fil et le point.
  def remove!
    transaction do
      if root?
        replies.each { |reply| reply.soft_delete!(validate: false) }
        soft_delete!(validate: false)
        map_feature.soft_delete!(validate: false)
      else
        soft_delete!(validate: false)
      end
    end
  end

  private

  def parent_is_root_of_same_point
    return if parent.nil?

    errors.add(:parent, "doit être le premier message du fil") unless parent.root?
    errors.add(:parent, "appartient à un autre point") unless parent.map_feature_id == map_feature_id
  end

  def single_root_per_point
    return unless root? && map_feature_id

    scope = MapComment.roots.where(map_feature_id: map_feature_id)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:base, "Ce point a déjà son fil de commentaires") if scope.exists?
  end

  def resolution_only_on_root
    errors.add(:resolved_at, "ne se pose que sur le premier message") if resolved_at.present? && !root?
  end
end
