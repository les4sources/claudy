# Une facture de vente enregistrée dans Claudy (epic #240, phase 6).
#
# **Claudy n'émet pas de facture de vente.** Elles sortent d'OkiOki : on en
# enregistre ici le numéro, la date, le client, les lignes et le PDF. Le
# registre sert à trois choses — retrouver une facture, savoir ce qu'il en
# reste à encaisser, et garantir qu'un séjour n'est jamais facturé deux fois.
#
# Deux façons d'arriver au grand livre (`posting_mode`, Michael 2026-10-30) :
#
# - `on_issue` : la facture n'a pas de réservation. Son enregistrement passe
#   l'écriture au journal Ventes (`Accounting::PostSalesInvoice`) : débit du
#   400000 sur le tiers, crédit des comptes 7 de ses lignes, et du 451000 si
#   l'entité est assujettie. Une correction contre-passe et repasse.
# - `on_payment` : la facture d'un séjour ou d'une réservation de la file
#   Facturation. AUCUNE écriture de vente (décision 8) : la recette arrive au
#   grand livre par la ventilation du séjour à l'encaissement ; une écriture de
#   vente en plus la compterait deux fois.
#
# Une note de crédit garde un montant POSITIF : c'est son type qui inverse
# l'écriture. Liée à la facture qu'elle corrige, elle en réduit le reste dû.
#
# Le paiement est un RAPPROCHEMENT, jamais une case cochée (décision 4) : une
# facture passe `paid` quand les lignes de trésorerie affectées sur elle
# couvrent son total, et redevient `issued` si on défait l'affectation.
# == Schema Information
#
# Table name: sales_invoices
#
#  id                  :bigint           not null, primary key
#  deleted_at          :datetime
#  issued_on           :date             not null
#  kind                :string           default("invoice"), not null
#  notes               :text
#  number              :string           not null
#  paid_on             :date
#  posted_at           :datetime
#  posting_mode        :string           default("on_payment"), not null
#  status              :string           default("issued"), not null
#  total_cents         :bigint           default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  credited_invoice_id :bigint
#  customer_id         :bigint
#  journal_entry_id    :bigint
#  legal_entity_id     :bigint           not null
#  third_party_id      :bigint
#
# Indexes
#
#  index_sales_invoices_on_credited_invoice_id         (credited_invoice_id)
#  index_sales_invoices_on_customer_id                 (customer_id)
#  index_sales_invoices_on_deleted_at                  (deleted_at)
#  index_sales_invoices_on_journal_entry_id            (journal_entry_id)
#  index_sales_invoices_on_legal_entity_id             (legal_entity_id)
#  index_sales_invoices_on_legal_entity_id_and_number  (legal_entity_id,number) UNIQUE
#  index_sales_invoices_on_status                      (status)
#  index_sales_invoices_on_third_party_id              (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (credited_invoice_id => sales_invoices.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (journal_entry_id => journal_entries.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#
class SalesInvoice < ApplicationRecord
  STATUSES = %w[issued paid].freeze

  STATUS_LABELS = {
    "issued" => "Émise",
    "paid" => "Payée"
  }.freeze

  KINDS = %w[invoice credit_note].freeze

  KIND_LABELS = {
    "invoice" => "Facture",
    "credit_note" => "Note de crédit"
  }.freeze

  POSTING_MODES = %w[on_issue on_payment].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  belongs_to :customer, optional: true
  # Le client au sens comptable : celui du 400000. Obligatoire sans réservation.
  belongs_to :third_party, optional: true
  # La facture qu'une note de crédit corrige.
  belongs_to :credited_invoice, class_name: "SalesInvoice", optional: true
  has_many :credit_notes, class_name: "SalesInvoice", foreign_key: :credited_invoice_id,
                          inverse_of: :credited_invoice, dependent: :restrict_with_error
  # L'écriture de vente : celle que la facture a passée (`on_issue`).
  belongs_to :journal_entry, optional: true
  has_many :sales_invoice_lines, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :sales_invoice
  accepts_nested_attributes_for :sales_invoice_lines, allow_destroy: true
  has_many :sales_invoice_sources, dependent: :destroy
  # Les lignes de trésorerie affectées sur cette facture : c'est elles qui
  # disent si elle est payée.
  has_many :cash_allocations, as: :document, dependent: :nullify

  has_one_attached :document

  monetize :total_cents

  validates :number, presence: true
  validates :number, uniqueness: { scope: :legal_entity_id, message: "existe déjà pour cette entité" }
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, inclusion: { in: KINDS }
  validates :posting_mode, inclusion: { in: POSTING_MODES }
  validates :third_party, presence: { message: "est obligatoire pour une facture sans réservation" }, if: :on_issue?
  validate :lines_cover_total, if: :on_issue?
  validate :credited_invoice_is_coherent
  validate :no_vat_for_exempt_entity
  validate :frozen_once_posted

  before_validation :compute_vat

  scope :ordered, -> { order(issued_on: :desc, id: :desc) }
  scope :issued, -> { where(status: "issued") }
  scope :paid, -> { where(status: "paid") }
  scope :in_period, ->(from, to) { where(issued_on: from..to) }
  scope :invoices, -> { where(kind: "invoice") }
  scope :credit_notes, -> { where(kind: "credit_note") }

  def issued? = status == "issued"
  def paid? = status == "paid"
  def credit_note? = kind == "credit_note"
  def on_issue? = posting_mode == "on_issue"
  def on_payment? = posting_mode == "on_payment"
  def posted? = posted_at.present?

  # Rattachée : l'écriture de vente existait avant la facture (reprise
  # Winbooks, pièce passée à la main) et la facture la pointe sans l'avoir
  # produite. Elle ne se contre-passe pas d'ici.
  def attached?
    journal_entry_id.present? && !(journal_entry&.source_type == "SalesInvoice" && journal_entry.source_id == id)
  end

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # « Payée » ne dit rien d'une note de crédit : elle est imputée sur la
  # facture qu'elle corrige, ou remboursée au client.
  def status_label
    return STATUS_LABELS.fetch(status, status) unless credit_note?
    return "À imputer" if issued?

    credited_invoice_id ? "Imputée" : "Remboursée"
  end

  def label = "#{credit_note? ? 'Note de crédit' : 'Facture'} #{number}"

  # Les objets facturés — un séjour, un ou plusieurs réservables d'espace.
  def sources = sales_invoice_sources.map(&:source).compact

  def stay_sources = sources.grep(Stay)

  # Le client affiché : le tiers, sinon le client de la facture, sinon celui
  # du séjour facturé.
  def customer_name
    return third_party.name if third_party
    return customer.decorate.display_name if customer && customer.respond_to?(:decorate)

    stay_sources.first&.customer&.then { |c| c.try(:organization_name).presence } ||
      [customer&.first_name, customer&.last_name].compact.join(" ").presence
  end

  def allocated_cents = cash_allocations.sum(:amount_cents)

  # Ce qui règle la facture : les lignes bancaires qui l'ont encaissée, et les
  # notes de crédit qui la corrigent. Une note de crédit liée à sa facture est
  # réglée d'office : elle s'impute sur elle.
  def settled_cents
    return total_cents if credit_note? && credited_invoice_id

    encaisse = cash_allocations.sum(:amount_cents).abs
    credit_note? ? encaisse : encaisse + credit_notes.sum(:total_cents)
  end

  def remaining_cents = [total_cents.to_i - settled_cents, 0].max

  # Les totaux des lignes, HTVA et TVA.
  def lines_net_cents = sales_invoice_lines.reject(&:marked_for_destruction?).sum(&:net_amount_cents)
  def lines_vat_cents = sales_invoice_lines.reject(&:marked_for_destruction?).sum { |line| line.vat_cents.to_i }

  # L'entité ventile-t-elle la TVA en 451000 ? La fondation est exemptée : tout
  # part au produit TTC.
  def vat_subject? = legal_entity&.vat_regime == "subject"

  private

  # La TVA des lignes tapées HTVA, taux par taux sur la somme des bases, comme
  # OkiOki la calcule. Une TVA donnée telle quelle (import) n'est pas refaite.
  def compute_vat
    lines = sales_invoice_lines.reject(&:marked_for_destruction?)

    lines.select(&:net_cents).each do |line|
      next if line.typed_vat_cents.nil?

      line.vat_cents = line.typed_vat_cents
      line.amount_cents = line.net_cents + line.vat_cents
    end

    calculees = lines.select { |line| line.net_cents && line.typed_vat_cents.nil? }
    calculees.group_by { |line| line.vat_rate.to_i }.each do |rate, typed|
      expected = (typed.sum(&:net_cents) * rate).quo(100).round
      typed.each { |line| line.vat_cents = (line.net_cents * rate).quo(100).round }
      typed.max_by { |line| line.net_cents.abs }.vat_cents += expected - typed.sum(&:vat_cents)
      typed.each { |line| line.amount_cents = line.net_cents + line.vat_cents }
    end
  end

  def lines_cover_total
    lines = sales_invoice_lines.reject(&:marked_for_destruction?)
    if lines.empty?
      errors.add(:base, "Une facture sans réservation a besoin d'au moins une ligne (compte de produit, montant).")
      return
    end

    couvert = lines.sum { |line| line.amount_cents.to_i }
    return if couvert == total_cents.to_i

    errors.add(:base, "Les lignes font #{Money.new(couvert, 'EUR').format} TVA comprise pour un total de " \
                      "#{Money.new(total_cents.to_i, 'EUR').format}.")
  end

  def credited_invoice_is_coherent
    return if credited_invoice.blank?

    errors.add(:credited_invoice, "ne se donne qu'à une note de crédit") unless credit_note?
    errors.add(:credited_invoice, "doit être une facture, pas une note de crédit") if credited_invoice.credit_note?
    errors.add(:credited_invoice, "n'est pas de la même entité") if credited_invoice.legal_entity_id != legal_entity_id
    errors.add(:credited_invoice, "ne peut pas être elle-même") if credited_invoice_id == id && id.present?
  end

  def no_vat_for_exempt_entity
    return if legal_entity.blank? || vat_subject?
    return if sales_invoice_lines.reject(&:marked_for_destruction?).all? { |line| line.vat_cents.to_i.zero? }

    errors.add(:base, "#{legal_entity.name} n'est pas assujettie à la TVA : ses lignes se facturent à 0 %.")
  end

  # Une facture dont l'écriture est passée ne se retouche pas en place : on
  # contre-passe d'abord (`SalesInvoices::Correct`), qui la remet à plat.
  def frozen_once_posted
    return if posted_at_was.blank? || !on_issue?

    touche = (changed & %w[legal_entity_id third_party_id number issued_on total_cents kind]).any? ||
             sales_invoice_lines.any? { |line| line.new_record? || line.changed? || line.marked_for_destruction? }
    errors.add(:base, "Cette facture est comptabilisée : elle se corrige par contre-passation.") if touche
  end
end
