# == Schema Information
#
# Table name: document_files
#
#  id                 :bigint           not null, primary key
#  deleted_at         :datetime
#  name               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  document_folder_id :bigint
#  uploaded_by_id     :bigint
#
# Indexes
#
#  index_document_files_on_deleted_at          (deleted_at)
#  index_document_files_on_document_folder_id  (document_folder_id)
#  index_document_files_on_uploaded_by_id      (uploaded_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (document_folder_id => document_folders.id)
#  fk_rails_...  (uploaded_by_id => users.id)
#
# Un fichier de la section Documents (Michael, 2026-11-12) : un PDF d'abord,
# mais tout type est accepté. Le contenu est la pièce Active Storage `file` ;
# `name` est le nom qu'on lit et qu'on renomme (l'extension d'origine reste).
#
# Le fichier ne sort JAMAIS par une adresse publique d'Active Storage : il
# passe par `Documents::FilesController` (download, raw, thumb), qui vérifie
# l'accès à la section à chaque demande.
class DocumentFile < ApplicationRecord
  include DocumentItem

  MAX_SIZE = 200.megabytes

  # Ce qui s'affiche dans la page même ; tout le reste se télécharge. Le SVG et
  # le HTML n'y sont pas exprès : servis tels quels, ils exécuteraient du code.
  INLINE_TYPES = %w[application/pdf image/png image/jpeg image/gif image/webp image/avif].freeze

  KINDS = {
    pdf: %w[application/pdf],
    image: %w[image/],
    video: %w[video/],
    audio: %w[audio/],
    sheet: %w[spreadsheet excel csv numbers],
    slides: %w[presentation powerpoint keynote],
    doc: %w[msword wordprocessing opendocument.text rtf pages],
    archive: %w[zip x-tar gzip x-7z rar],
    text: %w[text/ json xml markdown]
  }.freeze

  KIND_LABELS = {
    pdf: "PDF", image: "Image", video: "Vidéo", audio: "Audio", sheet: "Tableur", slides: "Présentation",
    doc: "Texte", archive: "Archive", text: "Texte brut", other: "Fichier"
  }.freeze

  has_paper_trail

  belongs_to :folder, class_name: "DocumentFolder", foreign_key: :document_folder_id, optional: true, inverse_of: :files
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :file

  validates :file, presence: { message: "manque" }
  validate :file_not_too_big

  def self.parent_column = :document_folder_id

  def content_type = file.attached? ? file.blob.content_type.to_s : ""

  def byte_size = file.attached? ? file.blob.byte_size.to_i : 0

  def extension = File.extname(name.to_s).delete(".").downcase.presence ||
                  File.extname(file.attached? ? file.filename.to_s : "").delete(".").downcase.presence

  def kind
    @kind ||= begin
      type = content_type
      found = KINDS.find { |_, needles| needles.any? { |needle| type.include?(needle) } }&.first
      found ||= :sheet if %w[xls xlsx ods csv numbers].include?(extension)
      found ||= :doc if %w[doc docx odt rtf pages].include?(extension)
      found ||= :slides if %w[ppt pptx odp key].include?(extension)
      found ||= :text if %w[txt md csv json].include?(extension)
      found || :other
    end
  end

  def kind_label = KIND_LABELS.fetch(kind)

  def pdf? = kind == :pdf

  def image? = kind == :image

  # Affichable dans la page par le navigateur (PDF, photo) ; la vidéo et le son
  # passent par leurs balises, le texte brut est lu côté serveur.
  def inline? = INLINE_TYPES.include?(content_type)

  def thumbnail? = image? && inline? && file.variable?

  def to_param = [id, File.basename(name.to_s, ".*").parameterize.presence].compact.join("-")

  private

  def file_not_too_big
    return unless file.attached? && byte_size > MAX_SIZE

    errors.add(:file, "dépasse #{MAX_SIZE / 1.megabyte} Mo")
  end
end
