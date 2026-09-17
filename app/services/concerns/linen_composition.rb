# Composition DRAPS d'un séjour depuis un `Reservations::Draft` (epic #260,
# phase 2, décision Michael 6). Concern PARTAGÉ par `Reservations::Builder`
# (création) et `Stays::AdminUpdater` (édition).
#
# Décision figée : les draps sont une option facturée par LIT, jamais par nuit —
# 10 € le lit simple, 20 € le lit double. Une ligne `LinenOrder` par TYPE de lit,
# rattachée DIRECTEMENT au séjour (`has_many :linen_orders`), SANS occupation
# calendrier : des draps ne bloquent aucune disponibilité, donc pas de `StayItem`,
# sur le modèle de `MealOrder`.
#
# La part draps du devis (`quote.linen_cents`) est VENTILÉE sur les lignes au
# prorata du tarif : elle est extraite de `lodging_only_cents`, jamais ajoutée
# par-dessus. Le total du séjour est donc inchangé par cette ventilation —
# même invariant que camping / van / hamacs.
module LinenComposition
  extend ActiveSupport::Concern

  # `distribute_cents` (ventilation largest-remainder) vit dans CampingComposition.
  include CampingComposition

  private

  # Entrées exploitables du draft : [{ kind:, count: }], types à zéro exclus.
  def draft_linen_entries(draft)
    Array(draft.try(:linens)).filter_map do |raw|
      entry = raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw
      kind  = entry[:kind].to_s
      count = entry[:count].to_i
      next if count < 1
      next unless LinenOrder::KINDS.include?(kind)

      { kind: kind, count: count }
    end
  end

  def draft_has_linens?(draft)
    draft_linen_entries(draft).any?
  end

  # Crée les `LinenOrder` du séjour. `total_price_cents` (= `quote.linen_cents`)
  # est ventilé sur les lignes au prorata `count × tarif` : la somme des
  # `price_cents` égale EXACTEMENT la part draps du devis.
  def persist_linen_orders!(stay:, draft:, total_price_cents:)
    entries = draft_linen_entries(draft)
    return [] if entries.empty?

    weights = entries.map { |e| e[:count] * linen_rate_for(e[:kind]) }
    prices  = distribute_cents(total_price_cents.to_i, weights)

    entries.each_with_index.map do |entry, idx|
      stay.linen_orders.create!(
        kind: entry[:kind], quantity: entry[:count],
        unit_price_cents: linen_rate_for(entry[:kind]),
        price_cents: prices[idx]
      )
    end
  end

  # Édition : on reconstruit intégralement les lignes (comme le camping et les
  # hamacs). Une ligne de draps ne porte ni validation ni état propre — rien à
  # préserver, donc rien à réconcilier ligne à ligne.
  def reconcile_linen_orders!(stay:, draft:, total_price_cents:)
    detach_linen_orders!(stay)
    persist_linen_orders!(stay: stay, draft: draft, total_price_cents: total_price_cents)
  end

  def detach_linen_orders!(stay)
    stay.linen_orders.each { |order| order.soft_delete!(validate: false) }
    stay.linen_orders.reset
  end

  # Tarif unitaire d'un type de draps, borné à 1 pour ne jamais annuler le poids
  # d'une ligne (un tarif nul rendrait la ventilation dégénérée).
  def linen_rate_for(kind)
    [Pricing::Catalog.linen_rate(kind).to_i, 1].max
  end
end
