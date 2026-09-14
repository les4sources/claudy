# Une note de frais — ou une note de mission (epic #241).
#
# Un seul modèle pour les deux (décision 1) : une note de mission est une note
# de frais dont les lignes sont des kilomètres. `kind` sépare les formulaires et
# les séquences de pièces ; le cycle de vie, l'écriture et le circuit de
# paiement sont les mêmes.
#
# Le cycle : `recorded` (la compta a encodé la feuille papier) → `processing`
# (la pièce a son numéro, l'écriture est au grand livre, la note attend son
# virement) → `paid`. Et `rejected`, avec son motif, pour une note qu'on refuse.
#
# Ce qui compte ici, c'est ce qui se fige et quand. Tant que la note est
# `recorded`, tout se corrige. Au passage en `processing`, la référence est
# attribuée pour de bon et l'écriture existe : la note devient un document
# comptable, et un document comptable ne se réécrit pas — il se contre-passe.
# == Schema Information
#
# Table name: expense_reports
#
#  id               :bigint           not null, primary key
#  deleted_at       :datetime
#  kind             :string           default("expenses"), not null
#  notes            :text
#  paid_notified_at :datetime
#  paid_on          :date
#  posted_at        :datetime
#  processed_on     :date
#  reference        :string
#  rejection_reason :text
#  sequence_number  :integer
#  status           :string           default("recorded"), not null
#  submitted_on     :date
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint
#  fiscal_year_id   :bigint
#  human_id         :bigint           not null
#  legal_entity_id  :bigint           not null
#
# Indexes
#
#  index_expense_reports_on_created_by_id    (created_by_id)
#  index_expense_reports_on_deleted_at       (deleted_at)
#  index_expense_reports_on_fiscal_year_id   (fiscal_year_id)
#  index_expense_reports_on_human_id         (human_id)
#  index_expense_reports_on_legal_entity_id  (legal_entity_id)
#  index_expense_reports_on_reference        (reference) UNIQUE
#  index_expense_reports_on_sequence         (fiscal_year_id,kind,sequence_number) UNIQUE
#  index_expense_reports_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (fiscal_year_id => fiscal_years.id)
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#
class ExpenseReport < ApplicationRecord
  KINDS = %w[expenses mileage].freeze
  KIND_LABELS = {
    "expenses" => "Note de frais",
    "mileage" => "Note de mission"
  }.freeze

  # Le préfixe de la pièce comptable, par type (décision 4). Chaque type tient
  # sa propre séquence : `NF-2026-014` et `NM-2026-003` coexistent sans se
  # marcher dessus.
  REFERENCE_PREFIXES = {
    "expenses" => "NF",
    "mileage" => "NM"
  }.freeze

  STATUSES = %w[recorded processing paid rejected].freeze
  STATUS_LABELS = {
    "recorded" => "Enregistrée",
    "processing" => "En traitement",
    "paid" => "Payée",
    "rejected" => "Rejetée"
  }.freeze

  # Les couleurs disent le reste à faire : gris = encodée, ambre = en attente de
  # virement, teal = réglée, rouge = refusée.
  STATUS_BADGE_CLASSES = {
    "recorded" => "bg-gray-100 text-gray-700",
    "processing" => "bg-amber-100 text-amber-800",
    "paid" => "bg-teal-100 text-teal-800",
    "rejected" => "bg-red-100 text-red-700"
  }.freeze

  # Les attributs qui décrivent la DÉPENSE. Une fois la pièce émise, ils ne
  # bougent plus. Le statut, les dates de paiement et les traces d'envoi, eux,
  # continuent d'avancer — c'est tout ce que la vie d'après autorise.
  FROZEN_ATTRIBUTES = %w[kind human_id legal_entity_id submitted_on notes reference
                         sequence_number fiscal_year_id].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :human
  belongs_to :legal_entity
  belongs_to :fiscal_year, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  has_many :expense_lines, -> { ordered }, dependent: :destroy, inverse_of: :expense_report
  has_many :journal_entries, as: :source, dependent: :restrict_with_error
  has_many :cash_allocations, as: :document, dependent: :restrict_with_error

  accepts_nested_attributes_for :expense_lines, allow_destroy: true,
                                                reject_if: ->(attrs) { attrs["label"].blank? && attrs["amount"].blank? && attrs["distance_km"].blank? }

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :rejection_reason, presence: { message: "est obligatoire pour rejeter une note" },
                               if: -> { status == "rejected" }
  validate :frozen_once_processed, on: :update

  scope :recent_first, -> { order(Arel.sql("COALESCE(submitted_on, created_at::date) DESC"), id: :desc) }
  scope :of_kind, ->(kind) { where(kind: kind) }
  scope :with_status, ->(status) { where(status: status) }
  scope :for_human, ->(human_id) { where(human_id: human_id) }
  scope :in_period, ->(from, to) { where(submitted_on: from..to) }
  scope :to_pay, -> { where(status: "processing") }

  def kind_label = KIND_LABELS.fetch(kind, kind)
  def status_label = STATUS_LABELS.fetch(status, status)
  def status_badge_classes = STATUS_BADGE_CLASSES.fetch(status, "bg-gray-100 text-gray-700")
  def reference_prefix = REFERENCE_PREFIXES.fetch(kind, "NF")

  def recorded?   = status == "recorded"
  def processing? = status == "processing"
  def paid?       = status == "paid"
  def rejected?   = status == "rejected"
  def posted?     = journal_entries.any?
  def mileage?    = kind == "mileage"

  # Le total vient TOUJOURS des lignes : aucune colonne ne le duplique, donc
  # aucune colonne ne peut le contredire. Sur une note figée, les lignes le sont
  # aussi — la somme ne bouge plus d'elle-même.
  def total_cents = expense_lines.sum(:amount_cents)

  def total_money = Money.new(total_cents, "EUR")

  # Tant que la note n'est pas passée en traitement, tout se corrige. Après,
  # plus rien : la pièce est au grand livre.
  def editable? = recorded?

  # Ce qui a déjà été affecté à cette note depuis la trésorerie. C'est ce qui
  # décidera du passage en `paid` (phase 3) ; la phase 1 s'en sert pour dire à
  # l'écran où en est le règlement.
  def settled_cents = cash_allocations.sum(:amount_cents).abs

  # L'écriture d'achat de la note — celle qui porte la dette au 440000.
  def journal_entry = journal_entries.find { |entry| entry.journal == "purchases" }

  def label
    "#{kind_label} #{reference.presence || "##{id}"} — #{human&.name}"
  end

  # Le prochain numéro de séquence pour un exercice et un type. L'appelant a
  # verrouillé l'exercice avant d'arriver ici (patron `PostDocument#next_number`) :
  # sans verrou, deux passations concurrentes prennent le même numéro et l'index
  # unique en fait échouer une au hasard.
  #
  # Les soft-deletées comptent : un numéro attribué ne se réattribue jamais,
  # sinon la séquence ment sur ce qui a existé.
  def self.next_sequence_number(fiscal_year_id:, kind:)
    highest = with_deleted do
      where(fiscal_year_id: fiscal_year_id, kind: kind).maximum(:sequence_number)
    end
    highest.to_i + 1
  end

  def self.format_reference(prefix:, year:, number:)
    "#{prefix}-#{year}-#{format('%03d', number)}"
  end

  private

  # Une note passée en traitement porte un numéro de pièce et une écriture :
  # changer son bénéficiaire ou son entité ferait mentir l'une des deux sans que
  # rien ne le signale. La correction passe par la contre-passation.
  def frozen_once_processed
    return if %w[recorded rejected].include?(status_was)
    return if (changed & FROZEN_ATTRIBUTES).empty?

    errors.add(:base,
               "Cette note est #{STATUS_LABELS.fetch(status_was, status_was).downcase} — " \
               "sa pièce comptable existe. Contre-passe l'écriture pour la corriger.")
  end
end
