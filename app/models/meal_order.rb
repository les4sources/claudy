# Commande de CUISINE — repas, buffet ou apéro (epic #66 phase 3, étendu par
# l'epic Cuisine #219 phase 1). Rattachée DIRECTEMENT au séjour (`has_many` sur
# Stay, comme `ExperienceBooking`), PAS via `StayItem` : un repas n'occupe pas le
# calendrier. `date` est nullable pour tolérer les repas du funnel public
# (forme `{kind, people}` sans date).
#
# Deux états INDÉPENDANTS cohabitent, et c'est volontaire (décision Michael
# 2026-09-06) :
#   - `status`     — où en est le CLIENT, tenu à la main par l'accueil ;
#   - `validation` — où en est la CUISINE, tenu par la personne qui cuisine.
# Une demande d'info acceptée par Stéphanie reste une demande d'info : elle ne
# compte pas dans le total du séjour tant que le client n'a pas demandé fermement.
# == Schema Information
#
# Table name: meal_orders
#
#  id                     :bigint           not null, primary key
#  bread_reminder_sent_at :datetime
#  cancellation_reason    :text
#  cost_cents             :integer
#  cost_notes             :text
#  date                   :date
#  deleted_at             :datetime
#  kind                   :string
#  moment                 :string
#  notes                  :text
#  people                 :integer          default(1), not null
#  price_cents            :integer
#  refusal_reason         :text
#  status                 :string           default("requested"), not null
#  unit_price_cents       :integer
#  validated_at           :datetime
#  validation             :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  responsible_human_id   :bigint
#  stay_id                :bigint           not null
#
# Indexes
#
#  index_meal_orders_on_deleted_at            (deleted_at)
#  index_meal_orders_on_responsible_human_id  (responsible_human_id)
#  index_meal_orders_on_status                (status)
#  index_meal_orders_on_stay_id               (stay_id)
#  index_meal_orders_on_validation            (validation)
#
# Foreign Keys
#
#  fk_rails_...  (responsible_human_id => humans.id)
#  fk_rails_...  (stay_id => stays.id)
#
class MealOrder < ApplicationRecord
  KINDS       = %w[repas trio buffet_vege buffet_viande apero].freeze
  MOMENTS     = %w[midi soir gouter].freeze
  STATUSES    = %w[inquiry requested confirmed cancelled].freeze
  VALIDATIONS = %w[pending accepted refused].freeze
  FAMILIES    = %w[repas buffet apero].freeze

  # Famille = qui cuisine. Elle porte le comportement (la famille `repas` passe
  # par la validation email de Stéphanie ; buffet et apéro par « je m'en charge »).
  KIND_FAMILIES = {
    "repas"         => "repas",
    "trio"          => "repas",
    "buffet_vege"   => "buffet",
    "buffet_viande" => "buffet",
    "apero"         => "apero"
  }.freeze

  # Source UNIQUE des libellés de type — vues admin, page client, fusion, emails.
  KIND_LABELS = {
    "repas"         => "Repas (midi ou soir)",
    "trio"          => "Formule trio (midi + goûter + soir)",
    "buffet_vege"   => "Buffet végétarien",
    "buffet_viande" => "Buffet avec viande",
    "apero"         => "Apéro produits locaux"
  }.freeze

  MOMENT_LABELS     = { "midi" => "Midi", "soir" => "Soir", "gouter" => "Goûter" }.freeze
  FAMILY_LABELS     = { "repas" => "Repas", "buffet" => "Buffet", "apero" => "Apéro" }.freeze
  STATUS_LABELS     = { "inquiry" => "Demande d'info", "requested" => "Demande ferme",
                        "confirmed" => "Confirmé", "cancelled" => "Annulé" }.freeze
  VALIDATION_LABELS = { "pending" => "En attente", "accepted" => "Acceptée",
                        "refused" => "Refusée" }.freeze

  # Champs dont le changement invalide un accord déjà donné par la cuisine.
  # Le prix, les notes, le responsable et les coûts n'en font PAS partie.
  VALIDATION_SENSITIVE_FIELDS = %w[kind date moment people].freeze

  belongs_to :stay
  belongs_to :responsible_human, class_name: "Human", optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents, allow_nil: true
  monetize :cost_cents, allow_nil: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :people, numericality: { only_integer: true, greater_than: 0 }
  validates :moment, inclusion: { in: MOMENTS }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :validation, inclusion: { in: VALIDATIONS }
  validates :refusal_reason, presence: { message: "est obligatoire pour un refus" }, if: :refused?

  # Visible partout : tout sauf ce qui est annulé côté client ou refusé côté cuisine.
  scope :active, -> { where.not(status: "cancelled").where.not(validation: "refused") }
  # Compte dans le total du séjour : une demande d'info ne facture rien.
  scope :billable, -> { where(status: %w[requested confirmed]).where.not(validation: "refused") }
  scope :pending_validation, -> { where(validation: "pending").where.not(status: "cancelled") }
  scope :chronological, -> { order(Arel.sql("date ASC NULLS LAST"), :id) }

  before_save :reset_validation_on_sensitive_change
  before_save :recompute_price

  def self.label_for(kind) = KIND_LABELS[kind.to_s] || kind.to_s.tr("_", " ").capitalize

  def label = self.class.label_for(kind)
  def moment_label = MOMENT_LABELS[moment.to_s]
  def family = KIND_FAMILIES[kind.to_s]
  def family_label = FAMILY_LABELS[family]
  def status_label = STATUS_LABELS[status.to_s]
  def validation_label = VALIDATION_LABELS[validation.to_s]

  STATUSES.each { |s| define_method("#{s}?") { status.to_s == s } }
  VALIDATIONS.each { |v| define_method("#{v}?") { validation.to_s == v } }

  def active?   = !cancelled? && !refused?
  def billable? = %w[requested confirmed].include?(status.to_s) && !refused?

  # Tarif €/pers effectivement appliqué : l'override de la ligne d'abord, le
  # barème (table `rates`, puis constante) ensuite.
  def unit_price_effective_cents
    unit_price_cents || Pricing::Catalog.meal_per_person_cents(kind).to_i
  end

  # Marge de la ligne, une fois le coût réel saisi (phase 5).
  def margin_cents
    return nil if cost_cents.nil?

    price_cents.to_i - cost_cents.to_i
  end

  private

  # `price_cents` reste le TOTAL de la ligne. On le recalcule dès qu'un de ses
  # facteurs bouge — jamais sur un simple changement de notes ou de statut, pour
  # qu'un total corrigé à la main survive au reste de l'édition.
  def recompute_price
    # Un total posé explicitement dans la MÊME sauvegarde fait foi : c'est la
    # correction à la main, et le devis du funnel qui persiste son propre montant.
    return if will_save_change_to_price_cents? && price_cents.present?
    return unless price_cents.nil? || will_save_change_to_kind? ||
                  will_save_change_to_people? || will_save_change_to_unit_price_cents?

    self.price_cents = unit_price_effective_cents * people.to_i
  end

  # Changer la date, le moment, le type ou le nombre de convives d'une demande
  # déjà acceptée rouvre la question côté cuisine : elle repasse en attente et la
  # phase 4 en préviendra le responsable. Un accord ou un refus posé dans la même
  # sauvegarde a le dernier mot.
  def reset_validation_on_sensitive_change
    return unless validation == "accepted"
    return if will_save_change_to_validation?
    return unless VALIDATION_SENSITIVE_FIELDS.any? { |f| will_save_change_to_attribute?(f) }

    self.validation   = "pending"
    self.validated_at = nil
  end
end
