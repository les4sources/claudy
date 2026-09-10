# @label Anneau de répartition
class Charts::DonutComponentPreview < ViewComponent::Preview
  Slice = Struct.new(:label, :color, :amount_cents, :state, keyword_init: true) do
    def missing_accounting? = state == :missing_accounting

    def missing_account? = state == :missing_account
  end

  # Les six activités d'accueil, toutes renseignées.
  def with_data
    render Charts::DonutComponent.new(slices: full_slices, year: 2024)
  end

  # L'année en cours : le bar et l'épicerie ne sont pas encore encodés.
  def with_missing_accounting
    render Charts::DonutComponent.new(slices: pending_slices, year: 2026)
  end

  # Aucune donnée du tout.
  def empty
    render Charts::DonutComponent.new(slices: zeroed_slices, year: 2019)
  end

  private

  def full_slices
    [
      slice("Hébergements", "#0d9488", 84_500_00),
      slice("Salles", "#c026d3", 21_300_00),
      slice("Coworking", "#f59e0b", 3_150_00),
      slice("Cuisine", "#ea580c", 12_800_00),
      slice("Bar", "#7c3aed", 20_060_36),
      slice("Épicerie", "#0891b2", 5_650_35)
    ]
  end

  def pending_slices
    full_slices.map do |item|
      next item unless %w[Bar Épicerie].include?(item.label)

      slice(item.label, item.color, 0, state: :missing_accounting)
    end
  end

  def zeroed_slices
    full_slices.map { |item| slice(item.label, item.color, 0) }
  end

  def slice(label, color, amount_cents, state: :present)
    Slice.new(label: label, color: color, amount_cents: amount_cents, state: state)
  end
end
