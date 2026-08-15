# == Schema Information
#
# Table name: paper_sheets
#
#  id                :bigint           not null, primary key
#  channel           :string           not null
#  deleted_at        :datetime
#  encoded_at        :datetime
#  entry_mode        :string           default("quantity"), not null
#  notes             :text
#  period_month      :date             not null
#  status            :string           default("open"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  encoded_by_id     :bigint
#  member_account_id :bigint
#
# Indexes
#
#  index_paper_sheets_on_deleted_at                (deleted_at)
#  index_paper_sheets_on_encoded_by_id             (encoded_by_id)
#  index_paper_sheets_on_member_account_id         (member_account_id)
#  index_paper_sheets_on_period_month_and_channel  (period_month,channel)
#
# Foreign Keys
#
#  fk_rails_...  (encoded_by_id => users.id)
#  fk_rails_...  (member_account_id => member_accounts.id)
#
class PaperSheet < ApplicationRecord
  CHANNELS = %w[bar grocery meal].freeze
  CHANNEL_LABELS = CatalogItem::CHANNEL_LABELS

  STATUSES = %w[open encoded archived].freeze
  STATUS_LABELS = {
    "open" => "À encoder",
    "encoded" => "Encodée",
    "archived" => "Archivée"
  }.freeze

  # Le tableur actuel contient des MONTANTS, recopiés à la main. La nouvelle vie
  # contiendra des QUANTITÉS, puisque le prix vit maintenant dans le catalogue.
  # L'écran accepte les deux et convertit — c'est ce qui permet de reprendre
  # l'existant sans changer d'habitude du jour au lendemain.
  ENTRY_MODES = %w[quantity amount].freeze
  ENTRY_MODE_LABELS = {
    "quantity" => "Je saisis des quantités",
    "amount" => "Je saisis des montants"
  }.freeze

  has_soft_deletion default_scope: true
  has_paper_trail

  belongs_to :member_account, optional: true
  belongs_to :encoded_by, class_name: "User", optional: true
  has_many :account_entries, dependent: :nullify

  has_one_attached :photo

  validates :period_month, presence: true
  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :entry_mode, inclusion: { in: ENTRY_MODES }

  before_validation :normalize_period

  scope :recent_first, -> { order(period_month: :desc, id: :desc) }

  def channel_label = CHANNEL_LABELS.fetch(channel, channel)
  def status_label = STATUS_LABELS.fetch(status, status)
  def quantity_mode? = entry_mode == "quantity"

  # Les écritures d'une fiche sont datées du dernier jour de son mois : c'est ce
  # qui les fait tomber dans le décompte du bon mois (phase 6).
  def entry_date = period_month.end_of_month

  def total_cents = account_entries.sum(:amount_cents)

  # Le catalogue du canal, à la date de la fiche : encoder mars 2024 doit
  # utiliser les prix de mars 2024.
  #
  # Les articles ACTIFS du canal, PLUS ceux que cette fiche porte déjà. Une fiche
  # de février 2022 contient une soixantaine d'articles qui ne sont plus vendus
  # (Atrium PAM, Grosse Bertha, Chips Lucien…) : les filtrer sur `active` rendrait
  # la fiche illisible et inencodable, et les laisser actifs polluerait l'écran du
  # mois courant de soixante lignes mortes. L'union règle les deux d'un coup —
  # chaque fiche montre exactement ses propres articles.
  def catalog_items
    used_ids = account_entries.where.not(catalog_item_id: nil).distinct.pluck(:catalog_item_id)
    scope = CatalogItem.for_channel(channel)
    scope = used_ids.any? ? scope.where(active: true).or(scope.where(id: used_ids)) : scope.active

    scope.ordered.includes(:catalog_prices)
  end

  def price_for(item) = item.price_on(entry_date)

  private

  def normalize_period
    self.period_month = period_month.beginning_of_month if period_month.present?
  end
end
