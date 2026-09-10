# == Schema Information
#
# Table name: batch_cooking_cooks
#
#  id                       :bigint           not null, primary key
#  portions                 :decimal(12, 3)   default(0.0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  batch_cooking_session_id :bigint           not null
#  human_id                 :bigint           not null
#
# Indexes
#
#  index_batch_cooking_cooks_on_human_id  (human_id)
#  index_bc_cooks_on_session              (batch_cooking_session_id)
#  index_bc_cooks_unique                  (batch_cooking_session_id,human_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (batch_cooking_session_id => batch_cooking_sessions.id)
#  fk_rails_...  (human_id => humans.id)
#

# Qui a cuisiné une session de batch cooking, et pour combien de portions
# (epic #246).
#
# La ligne pointe un `Human` — enfants compris : un enfant qui cuisine est payé
# comme un adulte, sur SON compte personnel. C'est ce qui oblige l'écran à
# proposer de créer la personne quand un `HouseholdMember` n'a pas de `human_id`.
#
# ⚠️ `Human` porte `default_scope -> { where(status: "active") }`. Une personne
# partie ferait donc disparaître son association — d'où `Human.unscoped` partout
# où on remonte le nom d'un cuisinier d'une session passée.
class BatchCookingCook < ApplicationRecord
  has_paper_trail

  belongs_to :session, class_name: "BatchCookingSession",
                       foreign_key: :batch_cooking_session_id,
                       inverse_of: :cooks
  belongs_to :human

  # Décimal, et zéro permis : cinq portions partagées entre deux cuisiniers
  # font deux parts et demie, et quelqu'un qui a donné un coup de main sans
  # part reste dans la liste — il ne gagne simplement rien.
  validates :portions, presence: true,
                       numericality: { greater_than_or_equal_to: 0 }
  validates :human_id, uniqueness: { scope: :batch_cooking_session_id,
                                     message: "cuisine déjà sur cette session" }

  # Le nom du cuisinier, y compris quand la personne a quitté le lieu.
  def human_name
    Human.unscoped.where(id: human_id).pick(:name) || "Personne ##{human_id}"
  end
end
