# Un gîte ou une salle représenté par un tracé de la carte (issue #370). Un
# tracé peut en représenter plusieurs (la Chevêche et la Hulotte, superposées
# dans le même bâtiment) ; un gîte ou une salle n'a qu'un tracé — index unique
# en base, message clair côté `MapFeature`.
#
# Pas de soft-delete : la liaison d'un tracé supprimé est effacée pour que le
# lieu redevienne « à tracer ». L'historique vit dans PaperTrail.
class MapFeatureVenue < ApplicationRecord
  has_paper_trail

  belongs_to :map_feature
  # `venue_type` n'est jamais pris tel quel d'un formulaire : il est validé
  # contre `MapFeature::LINKABLE_TYPES` avant d'être enregistré, donc seul un
  # type connu est jamais résolu.
  belongs_to :venue, polymorphic: true

  validates :venue_type, inclusion: { in: MapFeature::LINKABLE_TYPES.keys }

  def key = "#{venue_type}:#{venue_id}"
end
