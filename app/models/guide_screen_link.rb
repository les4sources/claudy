# == Schema Information
#
# Table name: guide_screen_links
#
#  id            :bigint           not null, primary key
#  label         :string
#  path          :string
#  screen        :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  guide_page_id :bigint           not null
#  user_id       :bigint
#
# Indexes
#
#  index_guide_screen_links_on_guide_page_id  (guide_page_id)
#  index_guide_screen_links_on_screen         (screen) UNIQUE
#  index_guide_screen_links_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (guide_page_id => guide_pages.id)
#  fk_rails_...  (user_id => users.id)
#
# « Voir la procédure » (Michael, 2026-10-19) : l'écran `screen`
# (`contrôleur#action`, ex. `finance/expense_reports#new`) renvoie à une page du
# Guide. Un écran n'a qu'une procédure ; une page peut en servir plusieurs.
# Posé depuis l'écran lui-même par un rédacteur du Guide (en-tête de page).
class GuideScreenLink < ApplicationRecord
  has_paper_trail

  # La page retirée du Guide n'est plus proposée (`default_scope` de la
  # suppression douce) : le lien se tait sans être effacé.
  belongs_to :page, class_name: "GuidePage", foreign_key: :guide_page_id, inverse_of: :screen_links
  belongs_to :user, optional: true

  validates :screen, presence: true, uniqueness: true, format: { with: %r{\A[a-z0-9_/]+#[a-z0-9_]+\z} }
  validates :path, format: { with: %r{\A/(?!/)}, allow_blank: true }

  # Les gestes qui rendent un formulaire en erreur montrent le même écran.
  ACTION_ALIASES = { "create" => "new", "update" => "edit" }.freeze

  def self.screen_key(controller_path, action_name)
    "#{controller_path}##{ACTION_ALIASES.fetch(action_name.to_s, action_name.to_s)}"
  end

  # Le lien de l'écran, si sa page est toujours au Guide.
  def self.for_screen(screen)
    link = find_by(screen: screen)
    link if link&.page
  end
end
