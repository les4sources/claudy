# Une écriture comptable en partie double.
#
# L'invariant tient en une ligne : la somme des débits égale la somme des
# crédits. C'est lui qui fait qu'une comptabilité se contredit toute seule quand
# on se trompe, au lieu d'attendre qu'un humain remarque l'écart six mois plus
# tard — et c'est pour lui qu'on a choisi la partie double alors que les seuils
# CSA ne l'imposaient pas.
#
# Une écriture ne se saisit JAMAIS à la main : elle est produite par un service
# de passation à partir d'un document métier (`source`). Un contrôleur qui
# appellerait `JournalEntry.create` casserait la promesse qui rend le système
# tenable — on encode un fait, l'application produit les deux côtés.
# == Schema Information
#
# Table name: journal_entries
#
#  id              :bigint           not null, primary key
#  deleted_at      :datetime
#  entry_date      :date             not null
#  journal         :string           not null
#  label           :string           not null
#  locked_at       :datetime
#  number          :integer          not null
#  posted_at       :datetime         not null
#  source_type     :string
#  whodunnit       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  fiscal_year_id  :bigint           not null
#  legal_entity_id :bigint           not null
#  reversal_of_id  :bigint
#  source_id       :bigint
#
# Indexes
#
#  index_journal_entries_on_deleted_at       (deleted_at)
#  index_journal_entries_on_entry_date       (entry_date)
#  index_journal_entries_on_fiscal_year_id   (fiscal_year_id)
#  index_journal_entries_on_legal_entity_id  (legal_entity_id)
#  index_journal_entries_on_sequence         (fiscal_year_id,journal,number) UNIQUE
#  index_journal_entries_on_single_reversal  (reversal_of_id) UNIQUE WHERE (reversal_of_id IS NOT NULL)
#  index_journal_entries_on_source           (source_type,source_id,journal) UNIQUE WHERE (source_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (fiscal_year_id => fiscal_years.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (reversal_of_id => journal_entries.id)
#
class JournalEntry < ApplicationRecord
  JOURNALS = %w[sales purchases bank cash misc opening].freeze
  JOURNAL_LABELS = {
    "sales" => "Ventes",
    "purchases" => "Achats",
    "bank" => "Banque",
    "cash" => "Caisse",
    "misc" => "Opérations diverses",
    "opening" => "À-nouveaux"
  }.freeze

  class Unbalanced < StandardError; end
  class Locked < StandardError; end

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :fiscal_year
  belongs_to :legal_entity
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :reversal_of, class_name: "JournalEntry", optional: true
  has_one :reversal, class_name: "JournalEntry", foreign_key: :reversal_of_id, dependent: :restrict_with_error
  has_many :journal_lines, dependent: :destroy

  validates :journal, inclusion: { in: JOURNALS }
  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :entry_date, :label, :posted_at, presence: true
  validate :balances
  validate :at_least_two_lines
  validate :entity_matches_fiscal_year
  validate :within_fiscal_year
  validate :fiscal_year_open, on: :create
  validate :immutability, on: :update

  before_destroy :refuse_destruction

  scope :ordered, -> { order(:entry_date, :id) }
  scope :in_period, ->(from, to) { where(entry_date: from..to) }
  scope :in_journal, ->(journal) { where(journal: journal) }

  def journal_label = JOURNAL_LABELS.fetch(journal, journal)
  def debit_cents = journal_lines.sum(&:debit_cents)
  def credit_cents = journal_lines.sum(&:credit_cents)
  def locked? = locked_at.present? || fiscal_year&.closed?
  def reference = "#{journal_label} #{fiscal_year&.label}/#{number}"

  private

  # L'équilibre est vérifié sur les lignes en mémoire ET sur les lignes
  # persistées : construire l'écriture avec ses lignes en une seule passe doit
  # échouer aussi vite qu'en deux.
  def balances
    lines = journal_lines.reject(&:marked_for_destruction?)
    return if lines.empty?

    debits = lines.sum { |line| line.debit_cents.to_i }
    credits = lines.sum { |line| line.credit_cents.to_i }
    return if debits == credits

    errors.add(:base, "Écriture déséquilibrée : #{debits} au débit, #{credits} au crédit")
  end

  # Une écriture en partie double a au moins deux lignes. Sans cette règle, une
  # écriture vide passe toutes les validations d'équilibre — 0 égale 0 — et
  # occupe un numéro de séquence pour ne rien dire.
  def at_least_two_lines
    lines = journal_lines.reject(&:marked_for_destruction?)
    return if lines.size >= 2

    errors.add(:base, "Une écriture en partie double porte au moins deux lignes")
  end

  # L'exercice appartient à une entité ; l'écriture aussi. Les laisser diverger
  # produirait une balance juste pour personne.
  def entity_matches_fiscal_year
    return if fiscal_year.blank? || legal_entity_id.blank?
    return if fiscal_year.legal_entity_id == legal_entity_id

    errors.add(:legal_entity, "n'est pas celle de l'exercice #{fiscal_year.label}")
  end

  def within_fiscal_year
    return if entry_date.blank? || fiscal_year.blank? || fiscal_year.covers?(entry_date)

    errors.add(:entry_date, "tombe hors de l'exercice #{fiscal_year.label}")
  end

  def fiscal_year_open
    return if fiscal_year.blank? || !fiscal_year.closed?

    errors.add(:base, "L'exercice #{fiscal_year.label} est clôturé — passe une écriture sur l'exercice ouvert")
  end

  # Une écriture verrouillée ne se corrige pas, elle se contre-passe. Sans ça,
  # la numérotation garderait des trous et le passé deviendrait négociable.
  def immutability
    return unless locked_at_was.present? || fiscal_year&.closed?
    return if (changed - %w[updated_at deleted_at]).empty?

    errors.add(:base, "Écriture verrouillée : contre-passe-la plutôt que de la modifier")
  end

  def refuse_destruction
    return unless locked?

    errors.add(:base, "Écriture verrouillée : elle se contre-passe, elle ne se supprime pas")
    throw :abort
  end
end
