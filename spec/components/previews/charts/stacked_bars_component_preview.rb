# @label Graphe en barres empilées
class Charts::StackedBarsComponentPreview < ViewComponent::Preview
  Serie = Struct.new(:label, :color, :monthly_cents, :total_cents, keyword_init: true)

  # Une année pleine : quatre hébergements et les chambres seules.
  def with_data
    render Charts::StackedBarsComponent.new(series: sample_series, year: 2026)
  end

  # Une année sans la moindre réservation confirmée.
  def empty
    render Charts::StackedBarsComponent.new(series: [], year: 2026)
  end

  # Un seul hébergement, concentré sur l'été.
  def single_series
    render Charts::StackedBarsComponent.new(series: [sample_series.first], year: 2026)
  end

  private

  def sample_series
    [
      serie("La Chevêche", "#0d9488", [120, 90, 210, 340, 480, 620, 810, 760, 430, 280, 150, 260]),
      serie("La Hulotte", "#7c3aed", [80, 60, 180, 260, 390, 540, 720, 690, 350, 210, 120, 300]),
      serie("Le Grand-Duc", "#ea580c", [0, 0, 140, 0, 260, 380, 520, 470, 0, 180, 0, 410]),
      serie("Tiny house", "#4d7c0f", [0, 0, 0, 60, 90, 140, 190, 180, 110, 40, 0, 0]),
      serie("Chambres seules", "#94a3b8", [30, 0, 40, 0, 60, 0, 90, 0, 50, 0, 20, 70])
    ]
  end

  def serie(label, color, monthly_euros)
    cents = monthly_euros.map { |euros| euros * 100 }
    Serie.new(label: label, color: color, monthly_cents: cents, total_cents: cents.sum)
  end
end
