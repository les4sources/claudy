# Ce que les dossiers et les fichiers de la section Documents (Michael,
# 2026-11-12) ont en commun : un nom unique parmi ses voisins, et la corbeille.
#
# À LA CORBEILLE = `deleted_at` posé. Jeter un dossier y envoie tout ce qu'il
# contient AU MÊME INSTANT : c'est ce qui permet de le restaurer d'un bloc, et
# à la corbeille de ne montrer que ce qu'on a jeté (pas chaque fichier d'un
# dossier jeté). Rien ne s'efface tant qu'on ne vide pas la corbeille.
#
# Pas de `has_soft_deletion` ici : sa portée par défaut cacherait les éléments
# jetés aux requêtes de la corbeille elle-même, qui en a besoin à chaque ligne.
module DocumentItem
  extend ActiveSupport::Concern

  included do
    scope :kept, -> { where(deleted_at: nil) }
    scope :trashed, -> { where.not(deleted_at: nil) }
    scope :named_like, lambda { |query|
      words = query.to_s.split.first(8)
      words.reduce(all) { |scope, word| scope.where("#{AccentFolding.sql("#{table_name}.name")} LIKE ?", AccentFolding.pattern(word)) }
    }

    before_validation { self.name = name.to_s.dup.force_encoding(Encoding::UTF_8).scrub.unicode_normalize(:nfc).squish.delete("/\\").presence }
    validates :name, presence: true, length: { maximum: 180 }
    validate :name_free_among_siblings, unless: :trashed?
  end

  class_methods do
    # « Contrat.pdf », sinon « Contrat (2).pdf », « Contrat (3).pdf »… : le
    # premier nom libre dans un dossier. Un envoi ne refuse jamais un fichier
    # pour un nom déjà pris, il le numérote.
    def available_name(name, folder_id, except: nil)
      ext = self == DocumentFile ? File.extname(name.to_s) : ""
      base = ext.present? ? name.to_s.delete_suffix(ext) : name.to_s
      taken = sibling_scope(folder_id, except: except).pluck(:name).map { |n| AccentFolding.fold(n) }.to_set
      candidate = name.to_s
      counter = 1
      candidate = "#{base} (#{counter += 1})#{ext}" while taken.include?(AccentFolding.fold(candidate))
      candidate
    end

    def sibling_scope(folder_id, except: nil)
      scope = kept.where(parent_column => folder_id)
      except ? scope.where.not(id: except) : scope
    end
  end

  def trashed? = deleted_at.present?

  def folder_key = self[self.class.parent_column]

  private

  def name_free_among_siblings
    return if name.blank?
    return unless will_save_change_to_name? || will_save_change_to_attribute?(self.class.parent_column) || will_save_change_to_deleted_at?

    folded = AccentFolding.fold(name)
    clash = self.class.sibling_scope(folder_key, except: id).pluck(:name).any? { |other| AccentFolding.fold(other) == folded }
    errors.add(:base, "« #{name} » existe déjà à cet endroit") if clash
  end
end
