# Dates du séjour en clair, pour le funnel public.
#
# « 24 octobre 2026 → 25 octobre 2026 » répétait l'année pour rien : sur un
# séjour qui tient dans une année, elle n'est écrite qu'une fois, à la fin
# (Michael, 2026-10-03). Un séjour à cheval sur deux années garde les deux.
module FunnelDatesHelper
  def stay_dates_label(arrival, departure)
    return "" unless arrival && departure

    full = "%-d %B %Y"
    if arrival.year == departure.year
      "#{l(arrival, format: '%-d %B')} → #{l(departure, format: full)}"
    else
      "#{l(arrival, format: full)} → #{l(departure, format: full)}"
    end
  end
end
