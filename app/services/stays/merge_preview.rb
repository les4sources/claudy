module Stays
  # Aperçu (dry-run) d'une fusion de séjours SANS RIEN MUTER. Calcule le résultat
  # qu'aurait `Stays::MergeService` : client conservé, dates en union, composition
  # complète groupée par type (avec provenance), nouveau total, déjà payé, solde,
  # et les avertissements pertinents.
  #
  # Garantie anti-divergence (epic #81) : la projection ici reproduit EXACTEMENT
  # l'arithmétique de `Stay#recompute_aggregates!` (total + dates) et de
  # `Stay#amount_paid_cents` (union `payments.stay_id` ∪ `payments.booking_id`)
  # appliquée à l'ensemble fusionné. Un test de cohérence vérifie que, sur un même
  # jeu de données, preview == résultat réel de la fusion.
  class MergePreview
    # Une ligne de composition projetée (hébergement, espace, repas, activité…).
    CompositionItem = Struct.new(:type, :label, :origin_stay_id, :from_target, :amount_cents, keyword_init: true)
    Warning = Struct.new(:kind, :message, keyword_init: true)
    SourceRef = Struct.new(:id, :customer_name, keyword_init: true)

    # Regroupe le résultat projeté pour la vue.
    Result = Struct.new(
      :target, :customer_name, :arrival_date, :departure_date,
      :total_cents, :paid_cents, :balance_cents,
      :composition, :sources, :warnings,
      keyword_init: true
    )

    attr_reader :target, :sources

    def initialize(target:, sources:)
      @target = target
      @sources = Array(sources).compact
    end

    def call
      arrival, departure = projected_dates

      Result.new(
        target:         target,
        customer_name:  target.customer&.name,
        arrival_date:   arrival,
        departure_date: departure,
        total_cents:    projected_total_cents,
        paid_cents:     projected_paid_cents,
        balance_cents:  projected_total_cents - projected_paid_cents,
        composition:    projected_composition,
        sources:        sources.map { |s| SourceRef.new(id: s.id, customer_name: s.customer&.name) },
        warnings:       build_warnings
      )
    end

    private

    def all_stays
      @all_stays ||= [target, *sources]
    end

    # --- Total : mirror de `recompute_aggregates!` sur l'ensemble fusionné ----
    # bookables (hébergement/espaces/camping/van) + activités ACTIVES + repas.
    def projected_total_cents
      all_stays.sum { |stay| computed_total_cents(stay) }
    end

    def computed_total_cents(stay)
      stay.bookables.sum { |b| b.try(:price_cents).to_i } +
        stay.experience_bookings.active.sum(&:price_cents) +
        stay.meal_orders.sum { |m| m.price_cents.to_i }
    end

    # --- Déjà payé : mirror de `Stay#amount_paid_cents` post-fusion -----------
    # Après fusion, la cible porte tous les StayItem (donc tous les booking_ids)
    # et tous les `payments.stay_id` ré-ancrés. On projette exactement cette
    # relation union pour ne jamais diverger du réel.
    def projected_paid_cents
      Payment.where(stay_id: all_stays.map(&:id))
             .or(Payment.where(booking_id: projected_booking_ids))
             .paid.sum(:amount_cents)
    end

    def projected_booking_ids
      all_stays.flat_map do |stay|
        stay.stay_items.select { |item| item.bookable_type == "Booking" }.map(&:bookable_id)
      end
    end

    # --- Dates : mirror exact de `recompute_aggregates!` sur l'union ----------
    def projected_dates
      items = all_stays.flat_map(&:bookables)
      arrivals   = items.filter_map { |b| b.try(:from_date) }
      departures = items.filter_map { |b| b.try(:to_date) }

      if arrivals.any? || departures.any?
        [arrivals.min || target.arrival_date, departures.max || target.departure_date]
      else
        # Séjours sans bookable daté (activités/repas seuls) : dériver des dates
        # portées par ces éléments, sinon conserver celles de la cible.
        derived = all_stays.flat_map(&:activity_and_meal_dates)
        derived.any? ? [derived.min, derived.max] : [target.arrival_date, target.departure_date]
      end
    end

    # --- Composition projetée, groupée par type, avec provenance --------------
    def projected_composition
      items = []
      all_stays.each do |stay|
        from_target = stay.id == target.id
        decorator = stay.decorate

        decorator.lodging_bookings.each { |b| items << item(:lodging, decorator.item_label(b), stay, from_target, b.try(:price_cents)) }
        decorator.space_bookings.each  { |b| items << item(:space,   decorator.item_label(b), stay, from_target, b.try(:price_cents)) }
        decorator.camping_bookings.each { |b| items << item(:camping, decorator.item_label(b), stay, from_target, b.try(:price_cents)) }
        decorator.van_bookings.each    { |b| items << item(:van,     decorator.item_label(b), stay, from_target, b.try(:price_cents)) }
        stay.experience_bookings.active.each { |eb| items << item(:activity, eb.experience.name, stay, from_target, eb.price_cents) }
        stay.meal_orders.each          { |m| items << item(:meal, m.label, stay, from_target, m.price_cents) }
      end
      items
    end

    def item(type, label, stay, from_target, amount_cents)
      CompositionItem.new(
        type:           type,
        label:          label,
        origin_stay_id: stay.id,
        from_target:    from_target,
        amount_cents:   amount_cents.to_i
      )
    end

    # --- Avertissements contextuels (ambre) -----------------------------------
    def build_warnings
      warnings = []

      overwritten = sources.select { |s| s.customer_id != target.customer_id }
      if overwritten.any?
        names = overwritten.map { |s| s.customer&.name }.compact_blank.uniq.join(", ")
        warnings << Warning.new(
          kind: :different_customers,
          message: "Clients différents : le client de la cible (#{target.customer&.name}) est conservé, ces clients seront écartés — #{names}."
        )
      end

      sources.each do |source|
        next unless source.payments.pending.any?

        warnings << Warning.new(
          kind: :pending_payment,
          message: "Le séjour ##{source.id} porte un paiement en attente — vérifier avant de fusionner."
        )
      end

      dupes = all_stays
              .select { |s| s.arrival_date.present? && s.departure_date.present? }
              .group_by { |s| [s.arrival_date, s.departure_date] }
              .select { |_dates, group| group.size > 1 }
      dupes.each do |dates, group|
        warnings << Warning.new(
          kind: :identical_dates,
          message: "Dates identiques (#{I18n.l(dates.first, format: :long)} → #{I18n.l(dates.last, format: :long)}) entre les séjours #{group.map { |s| "##{s.id}" }.join(', ')} — possible doublon."
        )
      end

      warnings
    end
  end
end
