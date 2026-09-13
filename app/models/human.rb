# == Schema Information
#
# Table name: humans
#
#  id            :bigint           not null, primary key
#  cycle_active  :boolean          default(FALSE)
#  deleted_at    :datetime
#  description   :text
#  email         :string
#  iban          :string
#  name          :string
#  photo         :string
#  roles_enabled :boolean          default(TRUE), not null
#  status        :string           default("active")
#  summary       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class Human < ApplicationRecord
  has_many :projects
  has_many :experiences
  has_many :services
  has_many :cycle_actions, dependent: :destroy
  has_many :delegated_cycle_actions, class_name: "CycleAction", foreign_key: :delegate_to_human_id

  has_one :user

  # Les pôles de la personne (epic #239, phase 4). La fiche et l'index en ont
  # besoin pour montrer où chacun s'engage ; l'appartenance elle-même continue
  # de se modifier depuis l'écran du pôle, pas ici.
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships

  has_and_belongs_to_many :tasks
  has_and_belongs_to_many :gathering_actions, join_table: :gathering_action_humans
  has_many :carried_agenda_items, class_name: "AgendaItem", foreign_key: :carrier_id, dependent: :nullify

  scope :cycle_active, -> { where(cycle_active: true) }
  # Membres pour lesquels la gestion des rôles (veilleur, nourrissage…) est
  # activée. Un membre avec `roles_enabled: false` reste dans l'équipe mais
  # n'apparaît plus dans les écrans d'assignation de rôles.
  scope :roles_enabled, -> { where(roles_enabled: true) }
  # Personnes pouvant recevoir un compte d'accès (un email est requis pour
  # créer le User Devise). Cf. epic #25 — Phase 2 (comptes porteurs).
  scope :with_email, -> { where.not(email: [nil, ""]) }

  self.table_name = "humans"

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  # L'IBAN du membre (epic #241) : c'est par lui que partira le virement d'une
  # note de frais. Chiffré au repos, comme celui d'un tiers — une coordonnée
  # bancaire n'a pas à être lisible dans un dump de base. Il ne sort jamais dans
  # l'API agent.
  encrypts :iban

  before_validation :normalize_iban

  validates :iban, iban: true, allow_blank: true

  mount_uploader :photo, HumanAvatarUploader

  default_scope -> { where(status: "active").order(:name) }

	validates :name,
            presence: true,
            uniqueness: true

  # Les humains actifs qu'on peut encore ajouter à ce pôle — ceux qui n'en sont
  # pas déjà membres. L'index unique de `team_memberships` interdit le doublon ;
  # le sélecteur évite d'avoir à le découvrir en cliquant.
  def self.ordered_addable_to(team)
    return ordered_all if team.blank? || team.new_record?

    where.not(id: TeamMembership.where(team_id: team.id).select(:human_id)).order(:name)
  end

  def self.ordered_all = order(:name)

  def inactive?
    self.status == "inactive"
  end

  # A un compte d'accès (User Devise) lié.
  def account?
    user.present?
  end

  # Peut recevoir un compte d'accès (un email est nécessaire et aucun compte
  # n'existe encore).
  def account_possible?
    email.present? && user.blank?
  end

  # L'IBAN ne s'affiche jamais en entier hors du formulaire : quatre caractères
  # suffisent à reconnaître le compte sans l'exposer.
  def iban_masked
    return nil if iban.blank?

    "•••• #{iban.last(4)}"
  end

  private

  def normalize_iban
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
