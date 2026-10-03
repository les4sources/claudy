# Les réglages des carnets de l'épicerie (epic #359, phase 3) : le compte de la
# fondation vers lequel pointent TOUS les QR EPC (décision 16 — même celui d'un
# artisan), et les compteurs des feuilles Épicerie et Boulangerie.
#
# Depuis la phase 4, la correspondance carnet → compte de produit : c'est d'elle
# que naissent les règles d'affectation par mot-clé (`Shop::SeedAllocationRules`).
#
# Une seule ligne : `ShopSetting.current`. Le dépôt est public, l'IBAN ne se
# code donc jamais en dur ; il se règle dans l'admin, et il est chiffré au
# repos comme celui des artisans.
# == Schema Information
#
# Table name: shop_settings
#
#  id                           :bigint           not null, primary key
#  beneficiary_name             :string
#  bic                          :string
#  bread_sheets_printed_count   :integer          default(0), not null
#  grocery_sheets_printed_count :integer          default(0), not null
#  iban                         :text
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  bread_account_id             :bigint
#  craft_account_id             :bigint
#  grocery_account_id           :bigint
#
# Indexes
#
#  index_shop_settings_on_bread_account_id    (bread_account_id)
#  index_shop_settings_on_craft_account_id    (craft_account_id)
#  index_shop_settings_on_grocery_account_id  (grocery_account_id)
#
# Foreign Keys
#
#  fk_rails_...  (bread_account_id => general_accounts.id)
#  fk_rails_...  (craft_account_id => general_accounts.id)
#  fk_rails_...  (grocery_account_id => general_accounts.id)
#
class ShopSetting < ApplicationRecord
  # Les carnets et leur compte de produit par défaut (décisions 14 et 18). Un
  # compte choisi dans l'admin l'emporte toujours ; un compte absent du plan
  # comptable n'est jamais créé ici — sans compte, pas de règle, et la tâche
  # `shop:seed_allocation_rules` le signale.
  NOTEBOOKS = %i[grocery bread craft].freeze
  DEFAULT_ACCOUNT_CODES = { grocery: "701002", bread: "701003", craft: "701005" }.freeze
  NOTEBOOK_LABELS = { grocery: "Épicerie", bread: "Boulangerie", craft: "Artisanat" }.freeze
  # Le mot-clé imprimé dans la communication du QR de chaque carnet (décision 3),
  # celui que la banque rapproche. L'artisanat a un mot-clé par artisan
  # (`Consignor#sheet_communication`).
  NOTEBOOK_KEYWORDS = { grocery: "EPICERIE", bread: "PAIN" }.freeze

  has_paper_trail

  belongs_to :grocery_account, class_name: "GeneralAccount", optional: true
  belongs_to :bread_account,   class_name: "GeneralAccount", optional: true
  belongs_to :craft_account,   class_name: "GeneralAccount", optional: true

  encrypts :iban

  before_validation :normalize_bank_fields

  validates :iban, iban: true, allow_blank: true
  validates :bic, format: { with: /\A[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?\z/, message: "n'est pas un BIC valide" },
                  allow_blank: true
  validates :beneficiary_name, length: { maximum: 70 }

  def self.current
    first_or_create!
  end

  # Tout ce qu'il faut pour un QR EPC : sans IBAN ni bénéficiaire, pas de QR.
  def bank_configured? = iban.present? && beneficiary_name.present?

  # Le numéro de la feuille qu'on imprime : le compteur avance d'un cran, sans
  # course possible entre deux impressions simultanées.
  def next_sheet_number!(kind)
    column = { grocery: :grocery_sheets_printed_count, bread: :bread_sheets_printed_count }.fetch(kind)
    self.class.where(id: id).update_all("#{column} = #{column} + 1")
    reload.public_send(column)
  end

  # Le compte de produit d'un carnet : celui choisi dans l'admin, sinon le
  # compte par défaut s'il existe au plan comptable, sinon rien. Mémorisé : la
  # file « À affecter » le demande pour chacune de ses lignes.
  def revenue_account(notebook)
    notebook = notebook.to_sym
    key = [notebook, public_send(:"#{notebook}_account_id")]
    @revenue_accounts ||= {}
    return @revenue_accounts[key] if @revenue_accounts.key?(key)

    @revenue_accounts[key] = public_send(:"#{notebook}_account") ||
                             GeneralAccount.actives.find_by(code: DEFAULT_ACCOUNT_CODES.fetch(notebook))
  end

  # « BE68 5390 0754 7034 » : l'IBAN tel qu'on l'écrit sous un QR.
  def formatted_iban = iban.to_s.scan(/.{1,4}/).join(" ")

  private

  def normalize_bank_fields
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
    self.bic = bic.to_s.gsub(/\s+/, "").upcase.presence
    self.beneficiary_name = beneficiary_name.to_s.strip.presence
  end
end
