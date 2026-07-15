module Stays
  # Garantit qu'un Booking porte un Stay (epic #26, Phase 3). IDEMPOTENT :
  #   - si le Booking a déjà un Stay vivant (has_one :stay through stay_item),
  #     on le renvoie sans rien créer ;
  #   - sinon on upserte le Customer par email (service partagé), on crée le Stay
  #     et le StayItem qui le relie au Booking.
  #
  # N'écrit JAMAIS sur le Booking (zéro perte de donnée). Ne pose PAS de
  # legacy_origin : ce n'est pas une reprise legacy mais le canal courant
  # admin/OTA — l'idempotence repose sur la présence du Stay vivant, pas sur un
  # marqueur d'import.
  #
  # Appelé par Bookings::CreateService (tout nouveau booking admin/OTA), par
  # Payments::CreateService (garantir un stay avant de rattacher le paiement) et
  # par la rake stays:backfill_missing (rattrapage rétroactif).
  class EnsureForBooking
    def self.call(booking)
      new(booking).call
    end

    def initialize(booking)
      @booking = booking
    end

    def call
      existing = live_stay_for(@booking)
      return existing if existing.present?

      ActiveRecord::Base.transaction do
        customer = Customers::UpsertByEmail.call(
          email: @booking.email,
          attrs: customer_attrs
        )
        stay = Stay.create!(
          customer: customer,
          source: source_for(@booking),
          status: @booking.status,
          arrival_date: @booking.from_date,
          departure_date: @booking.to_date,
          total_amount_cents: @booking.price_cents.to_i
        )
        # On n'arrive ici que si live_stay_for est nil (pas de StayItem vivant → Stay
        # vivant). Un StayItem vivant PEUT toutefois subsister en pointant vers un Stay
        # soft-deleted (état latent improbable) : dans ce cas on le REPOINTE vers le
        # Stay neuf plutôt que d'en créer un second — sinon deux StayItem vivants pour
        # un même booking (l'unicité est scoped sur stay_id, donc autorisés). find_or_
        # initialize garantit exactement UN StayItem vivant par booking.
        item = StayItem.find_or_initialize_by(bookable: @booking)
        item.stay = stay
        item.save!
        stay
      end
    end

    private

    # Clé d'idempotence : le Stay VIVANT rattaché au booking, lu FRAÎCHEMENT en
    # base (StayItem live + Stay live) plutôt que via le cache d'association du
    # booking — sinon un même objet booking passé deux fois (ou dont
    # l'association a été chargée avant la création du stay) recréerait un
    # doublon. Robuste au re-run comme à l'objet en mémoire non rechargé.
    def live_stay_for(booking)
      StayItem.find_by(bookable: booking)&.stay
    end

    def customer_attrs
      group_name = @booking.group_name.presence
      {
        first_name: @booking.firstname,
        last_name: @booking.lastname,
        phone: @booking.phone,
        organization_name: group_name,
        customer_type: group_name.present? ? "organization" : "individual"
      }
    end

    # Canal d'attribution du Stay : les résas OTA (airbnb / bookingdotcom) passent
    # par le même formulaire admin, distinguées par `platform`. Tout le reste
    # (web, direct, téléphone…) est de la saisie manuelle admin.
    def source_for(booking)
      case booking.platform.to_s
      when "airbnb", "bookingdotcom" then "ota"
      else "manual"
      end
    end
  end
end
