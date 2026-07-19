module Stays
  # Garantit qu'un SpaceBooking porte un Stay (epic #81, Phase 1). Pendant du
  # canal Booking (Stays::EnsureForBooking) : comble le trou par lequel les
  # SpaceBooking créés en admin direct (SpaceBookings::CreateService) restaient
  # orphelins, sans Stay.
  #
  # IDEMPOTENT :
  #   - si le SpaceBooking a déjà un Stay vivant (has_one :stay through stay_item),
  #     on le renvoie sans rien créer ;
  #   - sinon on upserte le Customer par email (service partagé), on crée le Stay
  #     et le StayItem qui le relie au SpaceBooking.
  #
  # N'écrit JAMAIS sur le SpaceBooking (zéro perte de donnée). Ne pose PAS de
  # legacy_origin : ce n'est pas une reprise legacy mais le canal courant admin —
  # l'idempotence repose sur la présence du Stay vivant, pas sur un marqueur
  # d'import.
  #
  # SpaceBooking soft-deleted : on ne crée RIEN et on renvoie nil. Un séjour ne
  # s'attache qu'à une réservation d'espace vivante (l'invariant du backfill est
  # borné aux SpaceBooking vivants).
  #
  # Appelé par SpaceBookings::CreateService (tout nouveau space_booking admin) et
  # par la rake stays:backfill_missing (rattrapage rétroactif).
  class EnsureForSpaceBooking
    def self.call(space_booking)
      new(space_booking).call
    end

    def initialize(space_booking)
      @space_booking = space_booking
    end

    def call
      # Un SpaceBooking soft-deleted ne reçoit pas de Stay : rien à ancrer.
      return nil if @space_booking.deleted?

      existing = live_stay_for(@space_booking)
      return existing if existing.present?

      ActiveRecord::Base.transaction do
        customer = Customers::UpsertByEmail.call(
          email: @space_booking.email,
          attrs: customer_attrs
        )
        stay = Stay.create!(
          customer: customer,
          # Pas de canal OTA pour les espaces : la saisie est toujours admin.
          source: "manual",
          status: @space_booking.status,
          arrival_date: @space_booking.from_date,
          departure_date: @space_booking.to_date,
          total_amount_cents: @space_booking.price_cents.to_i
        )
        # On n'arrive ici que si live_stay_for est nil (pas de StayItem vivant →
        # Stay vivant). Un StayItem vivant PEUT toutefois subsister en pointant
        # vers un Stay soft-deleted (état latent improbable) : dans ce cas on le
        # REPOINTE vers le Stay neuf plutôt que d'en créer un second. find_or_
        # initialize garantit exactement UN StayItem vivant par space_booking.
        item = StayItem.find_or_initialize_by(bookable: @space_booking)
        item.stay = stay
        item.save!
        stay
      end
    end

    private

    # Clé d'idempotence : le Stay VIVANT rattaché au space_booking, lu FRAÎCHEMENT
    # en base (StayItem live + Stay live) plutôt que via le cache d'association —
    # sinon un même objet passé deux fois (ou dont l'association a été chargée
    # avant la création du stay) recréerait un doublon. Robuste au re-run comme à
    # l'objet en mémoire non rechargé.
    def live_stay_for(space_booking)
      StayItem.find_by(bookable: space_booking)&.stay
    end

    def customer_attrs
      group_name = @space_booking.group_name.presence
      {
        first_name: @space_booking.firstname,
        last_name: @space_booking.lastname,
        phone: @space_booking.phone,
        organization_name: group_name,
        customer_type: group_name.present? ? "organization" : "individual"
      }
    end
  end
end
