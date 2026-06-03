# == Schema Information
#
# Table name: humans
#
#  id          :bigint           not null, primary key
#  name        :string
#  email       :string
#  photo       :string
#  summary     :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  status      :string           default("active")
#
class Human < ApplicationRecord
  has_many :projects
  has_many :experiences
  has_many :services
  has_many :cycle_actions, dependent: :destroy
  has_many :delegated_cycle_actions, class_name: "CycleAction", foreign_key: :delegate_to_human_id

  has_one :user

  has_and_belongs_to_many :tasks

  scope :cycle_active, -> { where(cycle_active: true) }
  # Personnes pouvant recevoir un compte d'accès (un email est requis pour
  # créer le User Devise). Cf. epic #25 — Phase 2 (comptes porteurs).
  scope :with_email, -> { where.not(email: [nil, ""]) }

  self.table_name = "humans"

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  mount_uploader :photo, HumanAvatarUploader

  default_scope -> { where(status: "active").order(:name) }

	validates :name,
            presence: true,
            uniqueness: true

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
end
