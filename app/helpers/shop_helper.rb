# Les montants des carnets de l'épicerie (epic #359) : un écart se lit avec son
# signe, et « juste » quand il tombe à zéro.
module ShopHelper
  def shop_euros(cents) = number_to_currency(cents.to_i / 100.0)

  def shop_gap(cents)
    return "juste" if cents.to_i.zero?

    "#{cents.positive? ? '+' : '−'}#{shop_euros(cents.abs)}"
  end

  def shop_gap_class(cents) = cents.to_i.zero? ? "text-emerald-700" : "text-orange-700"

  # La valeur d'un champ en euros : vide plutôt que « 0,00 » sur un brouillon neuf.
  def shop_euros_field(cents) = cents.to_i.zero? ? nil : format("%.2f", cents / 100.0).tr(".", ",")
end
