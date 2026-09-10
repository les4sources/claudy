# == Schema Information
#
# Table name: batch_cooking_servings
#
#  id                       :bigint           not null, primary key
#  portions                 :integer          not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  batch_cooking_session_id :bigint           not null
#  member_account_id        :bigint           not null
#
# Indexes
#
#  index_batch_cooking_servings_on_member_account_id  (member_account_id)
#  index_bc_servings_on_session                       (batch_cooking_session_id)
#  index_bc_servings_unique                           (batch_cooking_session_id,member_account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (batch_cooking_session_id => batch_cooking_sessions.id)
#  fk_rails_...  (member_account_id => member_accounts.id)
#

# Ce qu'un ménage a reçu d'une session de batch cooking (epic #246).
#
# La ligne pointe le COMPTE, pas le ménage : c'est le compte qui porte la
# charge, et un ménage peut en avoir plusieurs. Le compte est aussi ce qui
# survit à un ménage dissous.
class BatchCookingServing < ApplicationRecord
  has_paper_trail

  belongs_to :session, class_name: "BatchCookingSession",
                       foreign_key: :batch_cooking_session_id,
                       inverse_of: :servings
  belongs_to :member_account

  validates :portions, presence: true,
                       numericality: { only_integer: true, greater_than: 0 }
  validates :member_account_id, uniqueness: { scope: :batch_cooking_session_id,
                                              message: "est déjà servi sur cette session" }

  # Le total de la session se recompte depuis SES lignes, quel que soit le
  # chemin qui les écrit : formulaire imbriqué, console, service. Un compteur
  # qui ne se met à jour que dans le contrôleur ment dès le premier autre appel.
  after_save :refresh_session_total
  after_destroy :refresh_session_total

  private

  def refresh_session_total
    session&.refresh_total_portions!
  end
end
