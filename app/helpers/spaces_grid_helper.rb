# Textes de la grille « Espaces » (epic #234, phase 3) — partagés par le funnel
# public, la modification client et le formulaire admin, qui rendent tous le
# même partial `public/reservations/_spaces_calendar`.
#
# Deux textes, une seule vérité chacun :
#   · l'indication de tarif sous le nom de l'espace, DÉRIVÉE de `Pricing::Catalog`
#     (donc de Paramètres > Tarifs) et plus jamais recopiée en dur dans la vue ;
#   · le résumé en clair d'une ligne (« 5 journées · lun 8 → ven 12 »), rendu ici
#     au chargement et recalculé à l'identique par `spaces_calendar_controller.js`
#     à chaque clic. Les deux implémentations se suivent : toute modification de
#     format touche les deux.
module SpacesGridHelper
  # Abréviations FR des jours, indexées par `Date#wday`. Minuscules : elles
  # s'insèrent dans une phrase (« lun 8 → ven 12 »), pas dans un en-tête.
  SUMMARY_SHORT_DAYS = %w[dim lun mar mer jeu ven sam].freeze

  # Périodes qui comptent pour une journée / pour une soirée. « Journée et
  # soirée » compte dans les deux : c'est une journée ET une soirée.
  DAY_PERIODS     = %w[journee journee_et_soiree].freeze
  EVENING_PERIODS = %w[soiree journee_et_soiree].freeze

  # « 140 € /j · 90 € /soir · 525 € les 5 jours » — tarifs SEMAINE, comme le dit
  # le sous-titre de la section. Le forfait 5 jours n'existe pas pour tous les
  # espaces : il est simplement omis quand le catalogue ne le porte pas.
  def space_rate_hint(kind)
    day     = Pricing::Catalog.hall_rate_cents(kind, "journee")
    evening = Pricing::Catalog.hall_rate_cents(kind, "soiree")
    package = Pricing::Catalog.hall_package_cents(kind, "cinq_jours")

    parts = []
    parts << "#{compact_eur(day)}/j"          if day
    parts << "#{compact_eur(evening)}/soir"   if evening
    parts << "#{compact_eur(package)} les 5 jours" if package
    parts.join(" · ")
  end

  # Résumé d'une ligne de la grille. `periods` est le tableau brut du draft
  # (une entrée par jour, "" pour une case vide), `days` les dates-colonnes.
  # Rend nil quand la ligne est vide — l'appelant n'affiche alors rien.
  def spaces_summary_line(periods, days)
    periods = Array(periods).map(&:to_s)
    chosen  = days.each_with_index.reject { |_day, i| periods[i].to_s.empty? }
    return nil if chosen.empty?

    counts = []
    day_count     = periods.count { |p| DAY_PERIODS.include?(p) }
    evening_count = periods.count { |p| EVENING_PERIODS.include?(p) }
    counts << summary_count(day_count, "journée")           if day_count.positive?
    counts << "+ #{summary_count(evening_count, 'soirée')}" if evening_count.positive?

    first = summary_day_label(chosen.first.first)
    last  = summary_day_label(chosen.last.first)
    span  = first == last ? first : "#{first} → #{last}"

    (counts + [span]).join(" · ")
  end

  # « lun 8 » — abréviation du jour et quantième, sans le mois : la grille juste
  # au-dessus porte déjà les dates complètes.
  def summary_day_label(day)
    "#{SUMMARY_SHORT_DAYS[day.wday]} #{day.strftime('%-d')}"
  end

  private

  # « 1 journée », « 5 journées ». Pluralisation locale plutôt qu'empruntée au
  # `pluralize_fr` privé de `StaysMergeHelper` : deux modules d'aide ne se
  # doivent rien.
  def summary_count(count, singular)
    "#{count} #{count > 1 ? "#{singular}s" : singular}"
  end

  # « 140 € » et non « 140,00 € » : tous les montants du barème des salles sont
  # ronds, et l'indication doit tenir sous le nom de l'espace.
  def compact_eur(cents)
    humanized_money_with_symbol(Money.new(cents))
  end
end
