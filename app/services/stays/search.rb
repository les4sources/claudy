module Stays
  # Recherche plein texte de l'index Séjours (Michael 2026-07-26).
  #
  # Champs couverts, tous en insensible à la casse et aux accents partiels
  # (ILIKE %terme%) :
  #   - client        : prénom, nom, email ;
  #   - nom du groupe : `customers.organization_name` (client « organization »)
  #     ET la colonne `group_name` portée par CHAQUE type de bookable — c'est là
  #     que vit le nom de groupe des réservations réelles (« Les Scouts de
  #     Namur » saisi sur l'hébergement, pas sur la fiche client) ;
  #   - note INTERNE  : `stays.notes` MAIS AUSSI les notes portées par les
  #     bookables (`notes` sur les 5 types) — c'est là que vit la majorité des
  #     notes privées, exactement comme `StayDecorator#internal_notes_entries`
  #     les agrège à l'affichage. Chercher uniquement `stays.notes` aurait raté
  #     l'essentiel du corpus.
  #
  # IMPLÉMENTATION : trois `where` composés par `.or`, chacun adossé à une
  # SOUS-REQUÊTE plutôt qu'à une jointure. Deux raisons :
  #   1. `.or` exige une structure de jointures identique des deux côtés — trois
  #      `where` nus sur `stays` la garantissent trivialement ;
  #   2. le contrôleur enchaîne ensuite `.includes(...)` pour le preload de la
  #      page ; une `left_joins(:customer)` ici aurait produit une seconde
  #      jointure et des doublons de lignes.
  #
  # La relation retournée reste chaînable (filtre pills, tri, pagination).
  class Search
    # Longueur minimale : un terme d'un seul caractère ramènerait la table
    # entière pour un coût de scan inutile.
    MIN_LENGTH = 2

    def initialize(relation, query)
      @relation = relation
      @query    = query.to_s.strip
    end

    # Types de bookables rattachables à un séjour (miroir de la validation
    # d'inclusion de `StayItem#bookable_type`). Tous portent `notes` ET
    # `group_name` — la recherche les traite donc uniformément.
    BOOKABLE_TYPES = %w[Booking SpaceBooking CampingBooking VanBooking HamacBooking].freeze

    def call
      return @relation if @query.length < MIN_LENGTH

      by_customer.or(by_stay_note).or(by_bookable)
    end

    private

    attr_reader :relation, :query

    # `%` et `_` saisis par l'utilisateur sont échappés (`sanitize_sql_like`) :
    # une note contenant « 100% » se cherche littéralement.
    def term
      @term ||= "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    end

    def by_customer
      relation.where(customer_id: matching_customer_ids)
    end

    def by_stay_note
      relation.where("stays.notes ILIKE ?", term)
    end

    # Séjours dont AU MOINS UN bookable matche (note interne ou nom de groupe),
    # via `stay_items`.
    def by_bookable
      relation.where(id: stay_ids_with_bookable_match)
    end

    def matching_customer_ids
      Customer.where(
        "customers.first_name ILIKE :t OR customers.last_name ILIKE :t " \
        "OR customers.organization_name ILIKE :t OR customers.email ILIKE :t",
        t: term
      ).select(:id)
    end

    # Un `StayItem.where(type, id IN <sous-requête>)` par type de bookable,
    # assemblés par `.or`. Le soft-delete est déjà exclu par le default_scope de
    # chaque modèle : un bookable supprimé ne ramène jamais son séjour.
    def stay_ids_with_bookable_match
      BOOKABLE_TYPES
        .map { |type| stay_items_matching(type) }
        .reduce { |acc, rel| acc.or(rel) }
        .select(:stay_id)
    end

    def stay_items_matching(type)
      model = type.constantize
      table = model.table_name
      matching = model.where("#{table}.notes ILIKE :t OR #{table}.group_name ILIKE :t", t: term).select(:id)
      StayItem.where(bookable_type: type, bookable_id: matching)
    end
  end
end
