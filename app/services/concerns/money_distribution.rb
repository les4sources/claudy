# Répartition d'un montant en cents au prorata de poids, au plus fort reste.
#
# Extrait de `CampingComposition` (plan de cadrage, briques réutilisées) parce
# que trois usages en ont besoin : les plages de camping, la ventilation des
# recettes de séjour, et bientôt les commissions Stripe. Trois copies d'un
# algorithme d'arrondi, c'est trois occasions de perdre un centime à des
# endroits différents.
#
# L'invariant : la somme des parts vaut EXACTEMENT le total. Pas « à un centime
# près » — exactement. Un centime perdu dans un arrondi finit par un écart
# qu'on cherche des heures.
module MoneyDistribution
  module_function

  def distribute_cents(total, weights)
    total = total.to_i
    sum = weights.sum
    return Array.new(weights.size, 0) if sum <= 0

    base = weights.map { |w| total * w / sum }
    remainder = total - base.sum
    order = weights.each_index.sort_by { |i| [-((total * weights[i]) % sum), i] }
    remainder.times { |k| base[order[k % base.size]] += 1 }
    base
  end
end
