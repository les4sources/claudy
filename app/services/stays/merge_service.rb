module Stays
  # Fusion de séjours (epic #81, Phase 2). Réunit plusieurs Stay saisis
  # séparément — typiquement d'anciens Booking / SpaceBooking d'un même séjour
  # client, saisis chacun de leur côté — en un seul. Outil d'assainissement de
  # l'historique (jusqu'à 2023) : la robustesse sur données legacy imparfaites
  # prime, d'où des garde-fous stricts et une exécution tout-ou-rien.
  #
  # Calqué sur Customers::MergeService (source→cible, transaction, PaperTrail,
  # soft-delete des sources vidées).
  #
  # Règle déterministe : la CIBLE gagne. On ne touche JAMAIS au customer_id de
  # la cible, même si une source porte un client différent. Toutes les
  # occupations des sources migrent vers la cible :
  #   - StayItem (tous les bookables : Booking, SpaceBooking, CampingBooking,
  #     VanBooking) ;
  #   - MealOrder et ExperienceBooking (rattachés en direct via stay_id) ;
  #   - Payment (ancre stay_id, désormais obligatoire — issue #26 Phase 4).
  # Puis chaque source vidée est soft-deletée, et les agrégats de la cible sont
  # recalculés (dates = union, total recalculé, statut de paiement réévalué).
  class MergeService < ServiceBase
    attr_reader :target, :sources, :items_moved

    def self.call(target:, sources:)
      new(target: target, sources: sources).run
    end

    def initialize(target:, sources:)
      @target = target
      @sources = Array(sources).compact
      @items_moved = 0
    end

    def run
      return false unless valid_operands?

      catch_error(context: { target: target.id, sources: sources.map(&:id) }) do
        result = ActiveRecord::Base.transaction do
          # Verrou pessimiste : deux fusions concurrentes sur des ensembles qui
          # se recoupent (deux onglets, cibles croisées) passeraient toutes deux
          # les garde-fous lus hors transaction, et pourraient éparpiller des
          # occupations sur des séjours archivés. On verrouille les lignes puis
          # on re-vérifie l'état sous le verrou.
          raise ActiveRecord::Rollback unless lock_operands!

          sources.each { |source| absorb!(source) }
          # Les associations de la cible ont changé en base : on recharge avant de
          # recalculer, sinon `recompute_aggregates!` lirait un cache périmé.
          target.reload
          # Consolidation ADDITIVE des notes (principe P2 : rien ne se perd). On
          # rassemble sur le survivant les notes internes ET publiques de la cible,
          # des sources et de TOUS les bookables migrés, en une seule note interne
          # et une seule note publique. Les colonnes des bookables ne sont PAS vidées.
          consolidate_notes!
          target.recompute_aggregates!
          # `set_payment_status` est non-bang (partagé avec le webhook Stripe) :
          # ici, un échec silencieux violerait le tout-ou-rien de la fusion.
          unless target.set_payment_status
            set_error_message("Le statut de paiement n'a pas pu être recalculé : #{validation_errors_for(target)}")
            raise ActiveRecord::Rollback
          end
          true
        end
        result || false
      end
    end

    private

    # Garde-fous : refuse toute fusion ambiguë ou dangereuse plutôt que de
    # corrompre des données legacy. Chaque refus pose un message explicite.
    def valid_operands?
      return set_error_message("La cible est requise.") && false if target.nil?
      return set_error_message("Au moins une source est requise pour une fusion.") && false if sources.empty?
      return set_error_message("La cible ne peut pas figurer parmi les sources.") && false if sources.any? { |s| s.id == target.id }

      ids = sources.map(&:id)
      return set_error_message("Une même source est présente plusieurs fois.") && false if ids.uniq.length != ids.length

      return set_error_message("La cible est déjà supprimée.") && false if soft_deleted?(target)
      return set_error_message("Une source est déjà supprimée.") && false if sources.any? { |s| soft_deleted?(s) }

      true
    end

    # Verrouille toutes les lignes concernées (FOR UPDATE, ordre d'id stable
    # pour éviter les deadlocks) et re-vérifie sous le verrou qu'aucun séjour
    # n'a été supprimé entre les garde-fous et la transaction.
    def lock_operands!
      ids = ([target.id] + sources.map(&:id)).sort
      locked = Stay.unscoped.where(id: ids).lock("FOR UPDATE").to_a

      if locked.size != ids.size
        set_error_message("Un des séjours n'existe plus.")
        return false
      end
      if locked.any? { |stay| stay.deleted_at.present? }
        set_error_message("Un des séjours vient d'être supprimé (fusion concurrente ?). Recharge la page.")
        return false
      end

      true
    end

    # Migre toutes les occupations d'une source vers la cible, puis la vide.
    def absorb!(source)
      move_stay_items!(source)
      move_direct!(source.meal_orders)
      move_direct!(source.experience_bookings)
      move_payments!(source)

      # Source désormais vidée de toutes ses occupations : soft-delete (comme
      # Customers::MergeService, validate: false pour ne pas buter sur d'éventuels
      # invariants legacy). Le reload est OBLIGATOIRE : si l'appelant a préchargé
      # stay_items (includes du contrôleur), la cascade dependent: :destroy du
      # soft-delete relirait le cache d'association et supprimerait les items
      # pourtant déjà migrés vers la cible.
      source.reload
      source.soft_delete!(validate: false)
    end

    # StayItem polymorphe : Booking / SpaceBooking / CampingBooking / VanBooking.
    def move_stay_items!(source)
      source.stay_items.find_each do |item|
        item.update!(stay_id: target.id) # tracé PaperTrail
        @items_moved += 1
      end
    end

    # Éléments rattachés en direct au séjour (MealOrder, ExperienceBooking) :
    # simple bascule du stay_id.
    def move_direct!(relation)
      relation.find_each do |record|
        record.update!(stay_id: target.id)
        @items_moved += 1
      end
    end

    # Paiements rattachés à la source par leur ANCRE réelle (stay_id). On ne
    # s'appuie pas sur Stay#payments (qui unit aussi le lien historique
    # booking_id) : la fusion déplace l'ancre, pas les rattachements dérivés.
    def move_payments!(source)
      Payment.where(stay_id: source.id).find_each do |payment|
        payment.update!(stay_id: target.id) # tracé via PaymentVersion (PaperTrail)
        @items_moved += 1
      end
    end

    def soft_deleted?(stay)
      stay.deleted_at.present?
    end

    # --- Consolidation des notes (fusion) -----------------------------------
    # Réunit sur le survivant les notes éparpillées, sans jamais rien perdre ni
    # vider les colonnes d'origine des bookables. Écrit uniquement si le résultat
    # change quelque chose (aucune note nulle part → survivant inchangé).
    def consolidate_notes!
      consolidate_internal_notes!
      consolidate_public_notes!
    end

    # Note interne : texte brut. Ordre : note du séjour cible, notes des séjours
    # sources, PUIS notes internes de tous les bookables (cible + migrés). Ignore
    # les blancs, déduplique les contenus strictement identiques. Une seule note
    # → contenu tel quel ; plusieurs → en-têtes de provenance courts + jointure.
    def consolidate_internal_notes!
      entries = []
      entries << internal_entry("séjour ##{target.id}", target.notes)
      sources.each { |source| entries << internal_entry("séjour ##{source.id}", source.notes) }
      target.bookables.each do |bookable|
        entries << internal_entry(bookable_provenance(bookable), bookable_notes(bookable))
      end

      entries = dedup_internal(entries)
      return if entries.empty?

      consolidated =
        if entries.size == 1
          entries.first[:content]
        else
          entries.map { |e| "— Note de #{e[:label]} —\n#{e[:content]}" }.join("\n\n")
        end

      target.update!(notes: consolidated) if consolidated != target.notes
    end

    # Note publique : HTML ActionText. Rassemble les `public_notes` de la cible,
    # des sources et des bookables qui en portent (Booking, SpaceBooking). Une
    # seule → telle quelle ; plusieurs → concaténées, séparées par `<hr>`.
    # Déduplique les contenus HTML identiques.
    def consolidate_public_notes!
      htmls = []
      htmls << public_html(target)
      sources.each { |source| htmls << public_html(source) }
      target.bookables.each { |bookable| htmls << public_html(bookable) }

      htmls = htmls.compact.uniq
      return if htmls.empty?

      consolidated = htmls.size == 1 ? htmls.first : htmls.join("<hr>")
      target.public_notes = consolidated if consolidated != current_public_html(target)
    end

    # {label:, content:} d'une note interne, ou nil si le contenu est blanc.
    def internal_entry(label, content)
      text = content.to_s.strip
      return nil if text.blank?
      { label: label, content: text }
    end

    # Retire les nil et déduplique sur le CONTENU strict (garde la 1re provenance).
    def dedup_internal(entries)
      seen = {}
      entries.compact.each { |e| seen[e[:content]] ||= e }
      seen.values
    end

    # Provenance courte d'un bookable, p.ex. « La Hulotte (résa #345) ».
    def bookable_provenance(bookable)
      "#{bookable_label(bookable)} (résa ##{bookable.id})"
    end

    def bookable_label(bookable)
      case bookable
      when Booking      then bookable.lodging&.name.presence || "Hébergement"
      when SpaceBooking then bookable.spaces.map(&:name).compact_blank.join(", ").presence || "Espace"
      when CampingBooking then "Camping"
      when VanBooking     then "Van"
      else bookable.class.model_name.human
      end
    end

    # Colonne `notes` texte brut d'un bookable (Booking/SpaceBooking/Camping/Van).
    def bookable_notes(bookable)
      bookable.respond_to?(:notes) ? bookable.notes : nil
    end

    # HTML de la note publique d'un enregistrement (Stay/Booking/SpaceBooking) qui
    # porte `public_notes` (ActionText), ou nil si absent/vide.
    def public_html(record)
      return nil unless record.respond_to?(:public_notes)
      rich = record.public_notes
      return nil if rich.nil?
      body = rich.body
      return nil if body.nil? || body.to_plain_text.blank?
      body.to_html
    end
    alias current_public_html public_html
  end
end
