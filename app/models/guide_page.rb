# == Schema Information
#
# Table name: guide_pages
#
#  id               :bigint           not null, primary key
#  body             :text             default(""), not null
#  deleted_at       :datetime
#  last_edited_at   :datetime
#  position         :integer          default(0), not null
#  title            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  guide_chapter_id :bigint           not null
#  last_editor_id   :bigint
#
# Indexes
#
#  index_guide_pages_on_deleted_at                     (deleted_at)
#  index_guide_pages_on_guide_chapter_id_and_position  (guide_chapter_id,position)
#  index_guide_pages_on_last_editor_id                 (last_editor_id)
#
# Foreign Keys
#
#  fk_rails_...  (guide_chapter_id => guide_chapters.id)
#  fk_rails_...  (last_editor_id => users.id)
#
# Une page du Guide des 4 Sources (Michael, 2026-10-19). Le contenu est du
# Markdown (`body`), écrit dans l'éditeur visuel de Claudy ou par Claude via le
# serveur MCP. Toute modification passe par `Guide::SavePage`, qui écrit aussi
# une révision : c'est elle qui dit qui a contribué, et qui permet de revenir
# à une version précédente.
class GuidePage < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :chapter, class_name: "GuideChapter", foreign_key: :guide_chapter_id, inverse_of: :pages
  belongs_to :last_editor, class_name: "User", optional: true
  has_many :revisions, -> { order(created_at: :desc, id: :desc) }, class_name: "GuidePageRevision",
                                                                    inverse_of: :page, dependent: :destroy
  # Les images insérées dans la page, téléversées par l'éditeur (Active
  # Storage) : les rattacher à la page les tient à l'abri d'un nettoyage des
  # fichiers orphelins. Le Markdown, lui, pointe leur adresse permanente.
  has_many_attached :images
  # Les écrans de Claudy qui renvoient à cette page (« Voir la procédure »).
  has_many :screen_links, -> { order(:label, :screen) }, class_name: "GuideScreenLink",
                                                        inverse_of: :page, dependent: :destroy

  # « Ce qui change » : la note du formulaire, inscrite dans la révision.
  attr_accessor :summary

  validates :title, presence: true, length: { maximum: 160 }

  before_create do
    self.position = (GuidePage.where(guide_chapter_id: guide_chapter_id).maximum(:position) || 0) + 1 if position.to_i.zero?
  end

  scope :ordered, -> { order(:position, :id) }

  # Les pages des chapitres que ce compte lit (`GuideChapter.readable_by`).
  scope :readable_by, ->(user) { joins(:chapter).merge(GuideChapter.readable_by(user)) }

  # Recherche dans le titre et le contenu : chaque mot doit s'y trouver.
  scope :search, lambda { |query|
    words = query.to_s.split.first(8)
    next all if words.empty?

    words.reduce(all) do |scope, word|
      scope.where("guide_pages.title ILIKE :m OR guide_pages.body ILIKE :m", m: "%#{sanitize_sql_like(word)}%")
    end
  }

  def to_param = [id, title.to_s.parameterize.presence].compact.join("-")

  # Les personnes qui ont écrit la page, de la plus récente à la plus ancienne.
  def contributors
    ids = revisions.where.not(user_id: nil).group(:user_id).reorder(Arel.sql("MAX(created_at) DESC")).pluck(:user_id)
    users = User.where(id: ids).index_by(&:id)
    ids.filter_map { |id| users[id] }
  end

  # Les pages du Guide qui renvoient à celle-ci par `[[Titre]]`.
  def backlinks = Guide::Links.backlinks(self)

  # Un extrait lisible du contenu (sommaire, résultats de recherche) : le
  # Markdown débarrassé de sa syntaxe.
  def excerpt(length = 180)
    Guide::Markdown.plain_text(body).truncate(length, separator: " ")
  end

  # Range les pages dans l'ordre donné, dans un chapitre (glisser-déposer du
  # sommaire, y compris d'un chapitre à l'autre).
  def self.reorder!(chapter, ids)
    transaction do
      Array(ids).map(&:to_i).each_with_index do |id, index|
        where(id: id).update_all(guide_chapter_id: chapter.id, position: index + 1, updated_at: Time.current)
      end
    end
  end
end
