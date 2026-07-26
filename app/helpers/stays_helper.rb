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

  # Teinte de fond LÉGÈRE d'une ligne de l'index, par statut (Michael
  # 2026-07-26). Palier `-50` plein : c'est la nuance la plus claire de Tailwind,
  # donc déjà discrète, mais PERCEPTIBLE. Une première version à `-50/60`
  # (opacité 60 %) rendait un `rgba(243,250,247,.6)` indistinguable du blanc au
  # navigateur — une teinte de statut qu'on ne voit pas ne sert à rien.
  #
  # Le `hover:` monte d'un palier (`-100`) et est redéfini par statut, sinon le
  # `hover:bg-gray-50` générique effacerait la teinte au survol.
  ROW_STATUS_CLASSES = {
    "confirmed" => "bg-green-50 hover:bg-green-100",
    "pending"   => "bg-amber-50 hover:bg-amber-100",
    "canceled"  => "bg-red-50 hover:bg-red-100 text-gray-400",
    "cancelled" => "bg-red-50 hover:bg-red-100 text-gray-400"
  }.freeze

  def stay_row_classes(stay)
    ROW_STATUS_CLASSES.fetch(stay.status.to_s, "bg-white hover:bg-gray-50")
  end
end
