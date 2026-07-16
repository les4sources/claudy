# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  human_id               :bigint
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :human, optional: true

  # Distinction porteur / admin global pour le scoping de la validation
  # d'activités (epic #55, Phase 2). Le repo n'a PAS de rôle « admin » dédié
  # (ni Pundit/CanCan), et le compte d'accueil générique n'est rattaché à aucun
  # `Human` (cf. le fallback `current_user&.human || Human.first` de
  # BaseController). On s'appuie donc sur ce fait établi :
  #   * utilisateur SANS `human` = staff/accueil = admin global (voit tout) ;
  #   * utilisateur AVEC `human` = porteur, cloisonné à SES activités.
  # Règle « fail-closed » : un porteur ne voit jamais que les siennes, même s'il
  # n'en porte aucune (liste vide) — jamais toutes par accident.
  def porteur?
    human_id.present?
  end

  def global_admin?
    human_id.blank?
  end
end
