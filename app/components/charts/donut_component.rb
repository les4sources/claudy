# Un anneau de répartition, rendu en SVG côté serveur (issue #276). Même
# principe que `Charts::StackedBarsComponent` : aucune librairie de graphes,
# aucun JavaScript, aucune interactivité — un anneau, un total au centre, une
# légende qui porte tous les chiffres.
#
#   = render Charts::DonutComponent.new(slices: breakdown.activity_slices, year: @year)
#
# `slices` est une collection d'objets répondant à `label`, `color`,
# `amount_cents` et — pour les parts qui se lisent en comptabilité —
# `missing_accounting?` / `missing_account?`. Une part indisponible n'est JAMAIS
# masquée : elle apparaît dans la légende avec la raison de son absence, parce
# qu'une part qu'on retire en silence se lit comme une part qui n'existe pas.
class Charts::DonutComponent < ViewComponent::Base
  SIZE         = 220
  RADIUS       = 80
  STROKE_WIDTH = 30

  MISSING_ACCOUNTING_NOTE = "pas encore encodé en comptabilité".freeze
  MISSING_ACCOUNT_NOTE    = "compte comptable introuvable".freeze

  def initialize(slices:, year:, title: "Chiffre d'affaires Accueil — répartition")
    super()
    @slices = slices
    @year   = year
    @title  = title
  end

  attr_reader :slices, :year, :title

  def size = SIZE

  def radius = RADIUS

  def stroke_width = STROKE_WIDTH

  def center = SIZE / 2

  def circumference = 2 * Math::PI * RADIUS

  def total_cents = slices.sum { |slice| slice.amount_cents.to_i }

  def empty? = total_cents.zero?

  def total_amount = amount(total_cents)

  # Les arcs, déjà découpés : chaque part porte la longueur de son trait et son
  # décalage sur le cercle. Le `-90°` fait démarrer l'anneau en haut.
  def arcs
    @arcs ||= begin
      offset = 0.0
      slices.filter_map do |slice|
        cents = slice.amount_cents.to_i
        next if cents <= 0

        length = circumference * cents / total_cents
        arc = { color: slice.color, length: length, offset: -offset,
                label: "#{slice.label} — #{amount(cents)}" }
        offset += length
        arc
      end
    end
  end

  def legend_rows
    slices.map do |slice|
      { label: slice.label, color: slice.color, amount: amount(slice.amount_cents.to_i),
        share: share_of(slice.amount_cents.to_i), note: note_for(slice) }
    end
  end

  def description
    return "Aucun chiffre d'affaires Accueil enregistré pour #{year}." if empty?

    parts = slices.reject { |slice| slice.amount_cents.to_i.zero? }
                  .map { |slice| "#{slice.label} #{amount(slice.amount_cents.to_i)}" }
    "Répartition du chiffre d'affaires Accueil #{year}, pour un total de " \
      "#{amount(total_cents)} : #{parts.join(', ')}."
  end

  def amount(cents) = number_to_currency(cents / 100.0, unit: "€")

  def share_of(cents)
    return "—" if total_cents.zero?

    number_to_percentage(cents * 100.0 / total_cents, precision: 1)
  end

  private

  def note_for(slice)
    return MISSING_ACCOUNT_NOTE if slice.respond_to?(:missing_account?) && slice.missing_account?
    return MISSING_ACCOUNTING_NOTE if slice.respond_to?(:missing_accounting?) && slice.missing_accounting?

    nil
  end
end
