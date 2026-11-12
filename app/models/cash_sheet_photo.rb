# La photo de la feuille papier de caisse d'un mois (Michael, 2026-11-12).
#
# Au bar, la caisse se tient d'abord sur papier ; chaque mois, on reprend la
# feuille pour compléter les lignes de la feuille de caisse. Sa photo (ou un PDF
# scanné) reste jointe au mois, POUR RÉFÉRENCE : elle ne passe aucune écriture
# et se joint donc aussi à un mois arrêté.
#
# Une seule par caisse et par mois (index unique) : en joindre une autre
# remplace la précédente.
# == Schema Information
#
# Table name: cash_sheet_photos
#
#  id              :bigint           not null, primary key
#  month           :date             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  cash_account_id :bigint           not null
#  uploaded_by_id  :bigint
#
# Indexes
#
#  index_cash_sheet_photos_on_cash_account_id            (cash_account_id)
#  index_cash_sheet_photos_on_cash_account_id_and_month  (cash_account_id,month) UNIQUE
#  index_cash_sheet_photos_on_uploaded_by_id             (uploaded_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => cash_accounts.id)
#  fk_rails_...  (uploaded_by_id => users.id)
#
class CashSheetPhoto < ApplicationRecord
  # Ce que le navigateur sait afficher dans la page. Un HEIC passe (l'iPhone en
  # envoie parfois) mais s'ouvre en lien plutôt qu'en vignette.
  DISPLAYABLE_IMAGES = %w[image/jpeg image/png image/webp image/gif].freeze
  ACCEPTED_TYPES = (DISPLAYABLE_IMAGES + %w[image/heic image/heif application/pdf]).freeze
  MAX_SIZE = 25.megabytes

  has_paper_trail

  belongs_to :cash_account
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :file

  validates :month, presence: true, uniqueness: { scope: :cash_account_id }
  validate :file_acceptable

  before_validation { self.month = month.beginning_of_month if month.present? }

  def self.for(cash_account, month)
    find_by(cash_account: cash_account, month: month.beginning_of_month)
  end

  def displayable_image? = file.attached? && DISPLAYABLE_IMAGES.include?(file.content_type)
  def pdf? = file.attached? && file.content_type == "application/pdf"

  private

  def file_acceptable
    return errors.add(:base, "Choisis une photo ou un PDF de la feuille.") unless file.attached?

    unless ACCEPTED_TYPES.include?(file.content_type)
      errors.add(:base, "La feuille doit être une photo (JPEG, PNG, HEIC…) ou un PDF.")
    end
    errors.add(:base, "Le fichier dépasse 25 Mo.") if file.byte_size.to_i > MAX_SIZE
  end
end
