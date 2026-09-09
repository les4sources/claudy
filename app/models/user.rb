# == Schema Information
#
# Table name: users
#
#  id                        :bigint           not null, primary key
#  email                     :string           default(""), not null
#  encrypted_password        :string           default(""), not null
#  remember_created_at       :datetime
#  reset_password_sent_at    :datetime
#  reset_password_token      :string
#  restricted_to_experiences :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  human_id                  :bigint
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_human_id              (human_id)
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :human, optional: true

  # Cloisonnement des ACTIVITÉS (validation, édition, retrait, ajout sur un
  # séjour — `ExperienceBooking.for_user`, `ExperienceAvailability.for_user`).
  # Deux populations :
  #   * compte « Accès restreint aux activités » (interrupteur de la fiche
  #     membre, epic #25) = porteur externe : ne voit et n'agit que sur SES
  #     activités. Fail-closed : jamais toutes par accident, même s'il n'en
  #     porte aucune ou si son membre a été désactivé ;
  #   * tout autre compte = équipe / accueil : voit et édite tout.
  # Jusqu'au 2026-09-08 la règle était « compte AVEC `human` = porteur
  # cloisonné » (epic #55 phase 2, antérieure de quatre jours à
  # l'interrupteur) : toute l'équipe, Michael compris, tombait dans le
  # cloisonnement et ne pouvait rien faire depuis la modale séjour sur
  # l'activité d'un collègue.
  def restricted_to_own_activities?
    restricted_to_experiences?
  end

  # Compte sans membre d'équipe rattaché (accueil générique, compta). Le repo
  # n'a PAS de rôle « admin » dédié (ni Pundit/CanCan) : c'est ce fait établi
  # qui sert aux commentaires (`Comment#editable_by?`). Il ne gouverne PLUS le
  # cloisonnement des activités — cf. `#restricted_to_own_activities?`.
  def global_admin?
    human_id.blank?
  end

  # Membre d'équipe (Human) lié, sans le `default_scope` de Human (qui masque les
  # membres inactifs / soft-deleted) : indispensable pour détecter qu'un compte
  # est rattaché à un membre désactivé — l'association `user.human` renverrait
  # `nil` dans ce cas et laisserait passer la connexion.
  def linked_human
    return nil if human_id.blank?

    @linked_human ||= Human.unscoped.find_by(id: human_id)
  end

  # Un compte rattaché à un membre d'équipe INACTIF (statut ≠ "active") ne peut
  # plus se connecter, même si le User Devise est par ailleurs valide. Les
  # comptes purement admin (sans `human`) ne sont jamais concernés.
  def member_deactivated?
    h = linked_human
    h.present? && h.status != "active"
  end

  # Hook Devise : refuse l'authentification d'un compte dont le membre est
  # désactivé (contrôlé aussi à chaque requête via BaseController).
  def active_for_authentication?
    super && !member_deactivated?
  end

  def inactive_message
    member_deactivated? ? :account_deactivated : super
  end
end
