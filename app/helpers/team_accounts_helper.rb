# La mise en forme des comptes d'un pôle (page du pôle, Michael 2026-10-18).
module TeamAccountsHelper
  HEALTH_CLASSES = {
    good: "bg-teal-100 text-teal-800 ring-teal-200",
    watch: "bg-amber-100 text-amber-900 ring-amber-200",
    alert: "bg-rose-100 text-rose-800 ring-rose-200",
    none: "bg-gray-100 text-gray-600 ring-gray-200"
  }.freeze

  # « 1 234 € », sans centimes : la page se lit d'un coup d'œil. Avec `sign`,
  # un excédent porte son « + » et un déficit son « − ».
  def team_euros(cents, sign: false)
    amount = number_to_currency(cents.to_i.abs / 100.0, unit: "€", precision: 0)
    return amount unless sign
    return amount if cents.to_i.zero?

    "#{cents.to_i.negative? ? '−' : '+'}#{amount}"
  end

  def team_health_classes(level) = HEALTH_CLASSES.fetch(level, HEALTH_CLASSES[:none])

  # La part d'un budget consommée, en pourcentage entier (nil sans budget).
  def team_budget_percent(actual_cents, budget_cents)
    return nil unless budget_cents.to_i.positive?

    (actual_cents.to_f * 100 / budget_cents).round
  end
end
