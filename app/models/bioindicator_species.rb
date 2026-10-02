# La fiche d'une plante bio-indicatrice : « Renoncule rampante (Ranunculus
# repens) », ses biotopes, ses caractères indicateurs (ce qui lève la dormance
# de sa graine, donc ce qu'elle dit du sol), ses notes agronomique et
# écologique, et ses indicateurs codés.
#
# Remplie à la première rencontre de l'espèce dans un relevé de la couche
# « Bio-indicatrices » (analyse par Claude, par l'API), reprise ensuite par
# chaque relevé où elle reparaît : les analyses restent cohérentes et
# s'affinent. Distincte du catalogue nourricier (`PlantSpecies`) : une prêle ou
# un rumex n'ont rien à y faire.
#
# La clé est le nom latin (casse ignorée, une seule fiche vivante par espèce).
class BioindicatorSpecies < ApplicationRecord
  include BioindicatorVocabulary

  self.table_name = "bioindicator_species"

  has_paper_trail
  has_soft_deletion default_scope: true

  before_validation :normalize

  validates :name, presence: true, length: { maximum: 120 }
  validates :latin_name, presence: true, length: { maximum: 120 },
                         uniqueness: { case_sensitive: false, conditions: -> { where(deleted_at: nil) },
                                       message: "a déjà sa fiche" }
  validates :agronomy, inclusion: { in: AGRONOMY.keys }, allow_nil: true
  validates :ecology, inclusion: { in: ECOLOGY.keys }, allow_nil: true
  validate :indicators_are_known

  scope :ordered, -> { order(Arel.sql("lower(bioindicator_species.name)")) }
  scope :latin, ->(name) { where("lower(bioindicator_species.latin_name) = lower(?)", name.to_s.squish) }
  scope :search, lambda { |query|
    pattern = AccentFolding.pattern(query.to_s.squish)
    query.blank? ? all : where("#{AccentFolding.sql('bioindicator_species.name')} LIKE :q " \
                               "OR #{AccentFolding.sql('bioindicator_species.latin_name')} LIKE :q", q: pattern)
  }

  def to_s = name

  # « Renoncule rampante (Ranunculus repens) »
  def full_name = "#{name} (#{latin_name})"

  def agronomy_label = AGRONOMY[agronomy]
  def ecology_label = ECOLOGY[ecology]

  # [{ key:, label:, strength: }], du plus fort au plus léger.
  def indicator_list
    Array(indicators).sort_by { |item| -item["strength"].to_i }.map do |item|
      { key: item["key"], label: INDICATORS[item["key"]], strength: item["strength"].to_i }
    end
  end

  private

  def normalize
    %i[name latin_name family].each { |attribute| self[attribute] = self[attribute].to_s.squish.presence }
    %i[common_names description biotope_primary biotope_secondary indicator_traits notes].each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
    self.agronomy = agronomy.presence
    self.ecology = ecology.presence
    self.indicators = BioindicatorVocabulary.normalize_indicators(indicators || [])
  end

  def indicators_are_known
    BioindicatorVocabulary.indicator_errors(indicators).each { |message| errors.add(:base, message) }
  end
end
