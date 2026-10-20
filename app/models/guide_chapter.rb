# == Schema Information
#
# Table name: guide_chapters
#
#  id           :bigint           not null, primary key
#  access_roles :string           default([]), not null, is an Array
#  deleted_at   :datetime
#  description  :text
#  position     :integer          default(0), not null
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_guide_chapters_on_deleted_at  (deleted_at)
#  index_guide_chapters_on_position    (position)
#
# Un chapitre du Guide des 4 Sources (Michael, 2026-10-19) : « Arriver aux
# 4 Sources », « Procédures », « Coordonnées administratives »… Il ne porte que
# son titre, une phrase d'introduction et sa place dans le sommaire ; le
# contenu vit dans ses pages.
#
# Chaque chapitre dit quels rôles le lisent (`access_roles`, Michael
# 2026-10-19) ; les Sourciers lisent tout, sans qu'on ait à les cocher. Un
# chapitre décoché pour tous les rôles reste donc lisible par les Sourciers.
class GuideChapter < ApplicationRecord
  # Les rôles qu'on coche (le Sourcier lit tout d'office).
  READER_ROLES = (Access::ROLE_NAMES - %w[sourcier]).freeze
  # Un nouveau chapitre s'ouvre à tous, sauf aux porteurs d'activité : ils
  # viennent souvent d'en dehors du collectif, on leur ouvre un chapitre exprès.
  DEFAULT_READER_ROLES = (READER_ROLES - %w[porteur]).freeze

  attribute :access_roles, :string, array: true, default: -> { DEFAULT_READER_ROLES.dup }

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :pages, -> { order(:position, :id) }, class_name: "GuidePage", inverse_of: :chapter,
                                                  dependent: :restrict_with_error

  validates :title, presence: true, length: { maximum: 120 }
  before_validation { self.access_roles = Array(access_roles).map(&:to_s).compact_blank.uniq & READER_ROLES }

  before_create { self.position = (GuideChapter.maximum(:position) || 0) + 1 if position.to_i.zero? }

  scope :ordered, -> { order(:position, :id) }

  # Les chapitres que ce compte lit. Personne de connecté : aucun.
  scope :readable_by, lambda { |user|
    next none if user.nil?
    next all if user.reads_whole_guide?

    roles = user.guide_roles & READER_ROLES
    roles.empty? ? none : where("guide_chapters.access_roles && ARRAY[?]::varchar[]", roles)
  }

  def readable_by?(user)
    return false if user.nil?

    user.reads_whole_guide? || access_roles.intersect?(user.guide_roles)
  end

  # « Communication, Kid » : qui, en plus des Sourciers, lit ce chapitre.
  def reader_labels = READER_ROLES.select { |role| access_roles.include?(role) }.map { |role| Access.label(role) }

  def to_param = [id, title.to_s.parameterize.presence].compact.join("-")

  # Un chapitre qui a encore des pages ne se supprime pas : ses pages
  # disparaîtraient du sommaire sans qu'on l'ait voulu.
  def removable? = pages.none?

  # Range les chapitres dans l'ordre donné (glisser-déposer du sommaire).
  def self.reorder!(ids)
    transaction do
      Array(ids).map(&:to_i).each_with_index { |id, index| where(id: id).update_all(position: index + 1) }
    end
  end
end
