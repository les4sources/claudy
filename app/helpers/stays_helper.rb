# Helpers de présentation des séjours (epic #81, Phase 3).
module StaysHelper
  # Libellés français des canaux d'attribution (`Stay::SOURCES`). Partagés entre
  # le form séjour, l'index « Séjours récents » et son filtre.
  SOURCE_LABELS = {
    "manual"       => "Saisie manuelle",
    "ota"          => "OTA (Airbnb / Booking.com)",
    "reservation"  => "Réservation en ligne",
    "tally_legacy" => "Import Tally (legacy)"
  }.freeze

  def stay_source_label(value)
    SOURCE_LABELS[value.to_s] || value.to_s
  end
end
