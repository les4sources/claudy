# == Schema Information
#
# Table name: document_folders
#
#  id            :bigint           not null, primary key
#  deleted_at    :datetime
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#  parent_id     :bigint
#
# Indexes
#
#  index_document_folders_on_created_by_id  (created_by_id)
#  index_document_folders_on_deleted_at     (deleted_at)
#  index_document_folders_on_parent_id      (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (parent_id => document_folders.id)
#
# Un dossier de la section Documents (Michael, 2026-11-12). Les dossiers
# s'emboîtent (`parent`) sans limite de profondeur ; un dossier sans parent est
# à la racine (« Documents »). Voir `DocumentItem` pour la corbeille et les noms.
class DocumentFolder < ApplicationRecord
  include DocumentItem

  has_paper_trail

  belongs_to :parent, class_name: "DocumentFolder", optional: true, inverse_of: :children
  belongs_to :created_by, class_name: "User", optional: true
  has_many :children, class_name: "DocumentFolder", foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_exception
  has_many :files, class_name: "DocumentFile", foreign_key: :document_folder_id, inverse_of: :folder, dependent: :restrict_with_exception

  validate :not_inside_itself

  def self.parent_column = :parent_id

  # Du plus haut au plus proche, sans le dossier lui-même.
  def ancestors
    chain = []
    node = parent
    seen = Set.new
    while node && seen.add?(node.id)
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  # Ce dossier et tous ceux qu'il contient, à n'importe quelle profondeur.
  def subtree_ids
    self.class.subtree_ids([id])
  end

  def self.subtree_ids(ids)
    ids = Array(ids).compact
    return [] if ids.empty?

    sql = <<~SQL.squish
      WITH RECURSIVE tree(id) AS (
        SELECT id FROM document_folders WHERE id IN (:ids)
        UNION
        SELECT f.id FROM document_folders f JOIN tree ON f.parent_id = tree.id
      )
      SELECT id FROM tree
    SQL
    connection.select_values(sanitize_sql([sql, { ids: ids }])).map(&:to_i)
  end

  def path_label = (ancestors + [self]).map(&:name).join(" › ")

  def to_param = [id, name.to_s.parameterize.presence].compact.join("-")

  private

  # Un dossier ne se range ni dans lui-même ni dans un de ses sous-dossiers :
  # il se détacherait de l'arbre.
  def not_inside_itself
    return unless persisted? && will_save_change_to_parent_id? && parent_id

    errors.add(:parent, "ne peut pas être ce dossier ou un de ses sous-dossiers") if subtree_ids.include?(parent_id)
  end
end
