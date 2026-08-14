# == Schema Information
#
# Table name: recurring_charges
#
#  id                  :bigint           not null, primary key
#  active              :boolean          default(TRUE), not null
#  amount_cents        :integer
#  applies_to          :string           default("account"), not null
#  basis               :string           default("flat"), not null
#  deleted_at          :datetime
#  ends_on             :date
#  flow                :string
#  kind                :string
#  label               :string           not null
#  rate_key            :string
#  split_label         :string
#  split_rate_key      :string
#  starts_on           :date             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  household_member_id :bigint
#  member_account_id   :bigint
#
# Indexes
#
#  index_recurring_charges_on_deleted_at           (deleted_at)
#  index_recurring_charges_on_household_member_id  (household_member_id)
#  index_recurring_charges_on_member_account_id    (member_account_id)
#
# Foreign Keys
#
#  fk_rails_...  (household_member_id => household_members.id)
#  fk_rails_...  (member_account_id => member_accounts.id)
#
# Charge mensuelle récurrente d'un compte (issue #159).
#
# Le montant se résout À LA DATE du mois traité : un forfait revu à la hausse
# cette année ne doit pas réécrire les décomptes de 2024. Le multiplicateur
# aussi — `per_adult` compte les adultes DU MOIS, pas ceux d'aujourd'hui, sinon
# un enfant devenu majeur depuis ferait mentir tout l'historique.
class RecurringCharge < ApplicationRecord
  BASES = %w[flat per_person per_adult per_child].freeze
  BASIS_LABELS = {
    "flat" => "Forfait (montant fixe)",
    "per_person" => "Par personne (enfants compris)",
    "per_adult" => "Par adulte",
    "per_child" => "Par enfant"
  }.freeze

  # Périmètre d'application. Une règle vise soit UN compte, soit un GROUPE de
  # ménages — résolu au moment de la génération, si bien qu'un ménage créé après
  # coup est couvert sans que personne n'ait à y penser.
  SCOPES = %w[account resident_households member_households all_households].freeze
  SCOPE_LABELS = {
    "account" => "Un seul compte",
    "resident_households" => "Tous les ménages habitants",
    "member_households" => "Tous les ménages membres",
    "all_households" => "Tous les ménages"
  }.freeze

  has_soft_deletion default_scope: true
  has_paper_trail

  belongs_to :member_account, optional: true
  belongs_to :household_member, optional: true

  validates :label, presence: true
  validates :basis, inclusion: { in: BASES }
  validates :applies_to, inclusion: { in: SCOPES }
  validate :anchored_on_account_or_scope
  validates :starts_on, presence: true
  validates :flow, inclusion: { in: AccountEntry::FLOWS }, allow_blank: true
  validate :exactly_one_amount_source
  validate :ends_after_starts

  scope :ordered, -> { order(:label) }
  scope :enabled, -> { where(active: true) }

  # Les règles en vigueur sur le mois demandé. Une règle qui démarre en cours de
  # mois compte pour ce mois : la charge est mensuelle, pas prorata temporis.
  scope :active_on, lambda { |month|
    last_day = month.end_of_month
    enabled
      .where(starts_on: ..last_day)
      .where("recurring_charges.ends_on IS NULL OR recurring_charges.ends_on >= ?", month.beginning_of_month)
  }

  def basis_label = BASIS_LABELS.fetch(basis, basis)

  # Montant unitaire résolu à la date demandée, ou nil si la clé ne résout rien.
  def unit_amount_cents_on(date)
    return amount_cents if amount_cents.present?

    Pricing::Rates.cents(rate_key, on: date)
  end

  # Part scindée (la balançoire) résolue à la date, ou nil s'il n'y en a pas /
  # plus. `nil` n'est pas une erreur : c'est la règle qui s'éteint d'elle-même.
  def split_amount_cents_on(date)
    return nil if split_rate_key.blank?

    Pricing::Rates.cents(split_rate_key, on: date)
  end

  # Les comptes visés par cette règle. Pour un périmètre, la liste est calculée
  # à CHAQUE génération : une famille arrivée le mois dernier est donc couverte
  # sans qu'on ait eu à toucher la règle.
  def target_accounts
    return MemberAccount.where(id: member_account_id) if applies_to == "account"

    households = Household.all
    households = households.where(kind: "resident") if applies_to == "resident_households"
    households = households.where(kind: "member") if applies_to == "member_households"

    MemberAccount.where(active: true, household_id: households.select(:id)).ordered
  end

  def scope_label = SCOPE_LABELS.fetch(applies_to, applies_to)
  def scoped? = applies_to != "account"

  # Combien de fois le montant unitaire s'applique, pour un compte et un mois.
  # Le compte est passé en argument : une même règle sert plusieurs ménages, et
  # chacun a son propre effectif.
  def multiplier_on(month, account = member_account)
    return 1 if basis == "flat"

    household = account&.household
    return 0 if household.nil?

    on = month.beginning_of_month
    case basis
    when "per_person" then household.people_on(on)
    when "per_adult" then household.adults_on(on)
    when "per_child" then household.children_on(on)
    else 1
    end
  end

  private

  def anchored_on_account_or_scope
    if applies_to == "account" && member_account_id.blank?
      errors.add(:member_account_id, "est obligatoire pour une charge visant un seul compte")
    elsif applies_to != "account" && member_account_id.present?
      errors.add(:member_account_id, "doit rester vide pour une charge qui vise un groupe de ménages")
    end
  end

  def exactly_one_amount_source
    return if amount_cents.present? ^ rate_key.present?

    errors.add(:base, "Renseigne soit un montant fixe, soit une clé de barème — pas les deux, pas aucun")
  end

  def ends_after_starts
    return if ends_on.blank? || starts_on.blank?
    return if ends_on >= starts_on

    errors.add(:ends_on, "doit être postérieure ou égale à la date de début")
  end
end
