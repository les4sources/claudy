# Les réglages des carnets de l'épicerie (epic #359, phase 3) : le compte de la
# fondation vers lequel pointent TOUS les QR EPC (décision 16 — même celui d'un
# artisan), et les compteurs des feuilles Épicerie et Boulangerie.
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
#
class ShopSetting < ApplicationRecord
  has_paper_trail

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

  # « BE68 5390 0754 7034 » : l'IBAN tel qu'on l'écrit sous un QR.
  def formatted_iban = iban.to_s.scan(/.{1,4}/).join(" ")

  private

  def normalize_bank_fields
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
    self.bic = bic.to_s.gsub(/\s+/, "").upcase.presence
    self.beneficiary_name = beneficiary_name.to_s.strip.presence
  end
end
