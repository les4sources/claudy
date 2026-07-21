# Composition REPAS d'un séjour depuis un `Reservations::Draft` (epic #66,
# Phase 3). Concern PARTAGÉ par `Reservations::Builder` (création) et
# `Stays::AdminUpdater` (édition).
#
# Décision figée : un repas est une commande datée `{kind, date, people}`
# rattachée DIRECTEMENT au séjour (`has_many :meal_orders`), SANS occupation
# calendrier — donc pas de `StayItem`, sur le modèle d'`ExperienceBooking`. Le
# montant vient du barème B2C (`Pricing::Catalog::MEAL_PER_PERSON_CENTS`) — la
# même source que la ligne `:meal` du devis, donc aucun double-compte.
#
# `date` est nullable : le funnel public envoie des repas sans date
# (`{kind, people}`) ; on la tolère (le canal admin, lui, fournit une date).
module MealComposition
  extend ActiveSupport::Concern

  private

  # Entrées de repas exploitables du draft : [{ kind:, date:, people: }].
  def draft_meal_entries(draft)
    Array(draft.meals).filter_map do |raw|
      entry  = raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw
      kind   = entry[:kind].to_s
      people = entry[:people].to_i
      next if kind.blank? || people < 1
      next unless Pricing::Catalog.meal_kinds.include?(kind)
      { kind: kind, date: parse_meal_date(entry[:date]), people: people }
    end
  end

  def draft_has_meals?(draft)
    draft_meal_entries(draft).any?
  end

  # Prix TVAC d'une entrée repas (source unique = Catalog, comme `meal_lines`).
  def meal_entry_price_cents(entry)
    Pricing::Catalog.meal_per_person_cents(entry[:kind]).to_i * entry[:people].to_i
  end

  # Crée les MealOrder du séjour depuis les entrées du draft. Retourne la somme
  # des montants créés.
  def create_meal_orders!(stay, draft)
    draft_meal_entries(draft).sum(0) do |entry|
      order = stay.meal_orders.create!(
        kind:        entry[:kind],
        date:        entry[:date],
        people:      entry[:people],
        price_cents: meal_entry_price_cents(entry)
      )
      order.price_cents
    end
  end

  # Réconcilie les repas à l'édition : rebuild complet (petit volume). Les
  # anciennes commandes sont soft-deleted (PaperTrail + default_scope), les
  # nouvelles recréées depuis le draft.
  def reconcile_meals!(stay, draft)
    stay.meal_orders.each { |order| order.soft_delete!(validate: false) }
    create_meal_orders!(stay, draft)
  end

  def parse_meal_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
