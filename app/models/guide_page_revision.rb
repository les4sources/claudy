# == Schema Information
#
# Table name: guide_page_revisions
#
#  id            :bigint           not null, primary key
#  body          :text             default(""), not null
#  source        :string           default("web"), not null
#  summary       :string
#  title         :string           not null
#  created_at    :datetime         not null
#  guide_page_id :bigint           not null
#  user_id       :bigint
#
# Indexes
#
#  index_guide_page_revisions_on_guide_page_id_and_created_at  (guide_page_id,created_at)
#  index_guide_page_revisions_on_user_id                       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (guide_page_id => guide_pages.id)
#  fk_rails_...  (user_id => users.id)
#
# L'état complet d'une page du Guide après une modification : titre et
# Markdown, son auteur, et d'où elle vient (« web » = l'éditeur de Claudy,
# « mcp » = Claude au nom de l'auteur). Une révision ne se réécrit jamais ;
# restaurer une version en crée une nouvelle.
class GuidePageRevision < ApplicationRecord
  SOURCES = { "web" => "Claudy", "mcp" => "Claude" }.freeze

  belongs_to :page, class_name: "GuidePage", foreign_key: :guide_page_id, inverse_of: :revisions
  belongs_to :user, optional: true

  validates :title, presence: true
  validates :source, inclusion: { in: SOURCES.keys }

  def via_claude? = source == "mcp"

  def author_name = user&.display_name.presence || "Quelqu'un"

  # Le numéro de la version dans l'histoire de sa page (1 = la création).
  def number
    @number ||= GuidePageRevision.where(guide_page_id: guide_page_id)
                                 .where("created_at < :t OR (created_at = :t AND id <= :id)", t: created_at, id: id)
                                 .count
  end
end
