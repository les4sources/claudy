# == Schema Information
#
# Table name: guide_chapters
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  position    :integer          default(0), not null
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
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
class GuideChapter < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :pages, -> { order(:position, :id) }, class_name: "GuidePage", inverse_of: :chapter,
                                                  dependent: :restrict_with_error

  validates :title, presence: true, length: { maximum: 120 }

  before_create { self.position = (GuideChapter.maximum(:position) || 0) + 1 if position.to_i.zero? }

  scope :ordered, -> { order(:position, :id) }

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
