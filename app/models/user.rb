# == Schema Information
#
# Table name: users
#
#  id                        :bigint           not null, primary key
#  access_roles              :string           default([]), not null, is an Array
#  email                     :string           default(""), not null
#  encrypted_password        :string           default(""), not null
#  notify_by_email           :boolean          default(TRUE), not null
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

  # Les liens de connexion par e-mail (issue #306). `dependent: :destroy` :
  # supprimer un compte doit emporter ses liens vivants, sinon un lien déjà
  # envoyé survivrait à son destinataire.
  has_many :user_login_links, dependent: :destroy

  # Centre de notifications (epic #242, phase 2). `dependent: :destroy` : une
  # notification n'a aucun sens sans son destinataire.
  has_many :notifications, foreign_key: :recipient_id, inverse_of: :recipient, dependent: :destroy

  # Rôles d'accès (Michael, 2026-10-09) : ce que le compte peut ouvrir, cf.
  # `Access`. Plusieurs rôles possibles, leurs droits s'additionnent. Un
  # compte sans rôle ne voit rien d'autre que la page qui le lui dit.
  before_validation { self.access_roles = Array(access_roles).map(&:to_s).compact_blank.uniq }
  validate :access_roles_must_be_known

  scope :with_access_role, ->(role) { where("? = ANY(access_roles)", role.to_s) }

  def sourcier? = access_roles.include?("sourcier")

  # `:write`, `:read` ou `nil` sur une section (`Access::SECTIONS`, ou `:full`
  # pour ce qui est réservé aux Sourciers).
  def access_level(section) = Access.level(access_roles, section)

  def can_read?(section) = access_level(section).present?

  def can_write?(section) = access_level(section) == :write

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

  # Compteur de la cloche. Plafonné à l'affichage par la vue, pas ici : le
  # nombre exact sert aussi aux specs.
  def unread_notifications_count
    notifications.unread.count
  end

  # Nom affiché dans un fil ou une notification : le membre d'équipe quand il y
  # en a un, sinon l'adresse email — même règle que `Comment#author_label`.
  def display_name
    linked_human&.name.presence || email.to_s
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

  private

  def access_roles_must_be_known
    unknown = access_roles - Access::ROLE_NAMES
    errors.add(:access_roles, "inconnu : #{unknown.to_sentence}") if unknown.any?
  end
end
