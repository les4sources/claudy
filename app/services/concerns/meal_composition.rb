# Composition CUISINE d'un séjour depuis un `Reservations::Draft` (epic #66
# phase 3, réconciliation par identifiant : epic Cuisine #219 phase 1). Concern
# PARTAGÉ par `Reservations::Builder` (création) et `Stays::AdminUpdater`
# (édition).
#
# Décision figée : une ligne de cuisine est une commande datée
# `{kind, date, moment, people, notes}` rattachée DIRECTEMENT au séjour
# (`has_many :meal_orders`), SANS occupation calendrier — donc pas de `StayItem`,
# sur le modèle d'`ExperienceBooking`. Le montant vient du barème
# (`Pricing::Catalog`) — la même source que la ligne `:meal` du devis, donc aucun
# double-compte.
#
# `date` est nullable : le funnel public envoie des repas sans date
# (`{kind, people}`) ; on la tolère (le canal admin, lui, fournit une date).
module MealComposition
  extend ActiveSupport::Concern

  private

  # Entrées exploitables du draft : [{ id:, kind:, date:, moment:, people:, notes: }].
  def draft_meal_entries(draft)
    Array(draft.meals).filter_map do |raw|
      entry  = raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw
      kind   = entry[:kind].to_s
      people = entry[:people].to_i
      next if kind.blank? || people < 1
      next unless Pricing::Catalog.meal_kinds.include?(kind)

      { id:     entry[:id].presence&.to_i,
        kind:   kind,
        date:   parse_meal_date(entry[:date]),
        moment: parse_meal_moment(entry[:moment]),
        people: people,
        notes:  entry[:notes].presence }
    end
  end

  def draft_has_meals?(draft)
    draft_meal_entries(draft).any?
  end

  # Prix TVAC d'une entrée (source unique = Catalog, comme `meal_lines`).
  def meal_entry_price_cents(entry)
    Pricing::Catalog.meal_per_person_cents(entry[:kind]).to_i * entry[:people].to_i
  end

  # Crée les MealOrder du séjour depuis les entrées du draft. Retourne la somme
  # des montants créés. Le prix est recalculé par le modèle (`before_save`).
  def create_meal_orders!(stay, draft)
    draft_meal_entries(draft).sum(0) { |entry| create_meal_order!(stay, entry).price_cents.to_i }
  end

  # Réconciliation PAR IDENTIFIANT à l'édition du séjour (#219). L'ancien
  # rebuild complet (soft-delete puis recréation) rendait volatil tout ce que la
  # ligne porte désormais : validation de la cuisine, responsable, prix corrigé,
  # coûts. Une correction d'heure d'arrivée ne doit rien effacer de cela.
  #
  # Le formulaire du séjour ne pilote QUE la prestation elle-même : type, date,
  # moment, convives, notes. Le prix unitaire surchargé, le responsable, le
  # statut client, la validation et les coûts ne sont jamais écrasés par lui.
  def reconcile_meals!(stay, draft)
    existing = stay.meal_orders.active.index_by(&:id)
    kept     = []

    draft_meal_entries(draft).each do |entry|
      order = entry[:id] && existing[entry[:id]]

      if order
        order.update!(entry.slice(:kind, :date, :moment, :people, :notes))
        kept << order.id
      elsif entry[:id].nil?
        # Ligne neuve. Une entrée qui porte un `id` étranger au séjour est
        # ignorée : params forgés ou draft recopié d'un autre séjour.
        kept << create_meal_order!(stay, entry).id
      end
    end

    (existing.keys - kept).each do |id|
      existing[id].update!(status: "cancelled", cancellation_reason: "Retirée du séjour")
    end

    stay.meal_orders.billable.sum(:price_cents)
  end

  def create_meal_order!(stay, entry)
    stay.meal_orders.create!(entry.slice(:kind, :date, :moment, :people, :notes))
  end

  def parse_meal_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_meal_moment(value)
    value = value.to_s
    MealOrder::MOMENTS.include?(value) ? value : nil
  end
end
