class AddSpaceBookingToPayments < ActiveRecord::Migration[7.0]
  # Provenance de facturation des espaces (facturation espaces → paiements).
  #
  # Un SpaceBooking porte son moyen et son statut de paiement dans ses colonnes
  # (`payment_method`, `payment_status`, `paid_amount_cents`, …) — mais AUCUN
  # Payment. La rake `space_bookings:billing_to_payments` transforme ces données
  # en Payment rattachés au Stay. Cette colonne enregistre le SpaceBooking
  # d'origine du Payment ; elle joue deux rôles :
  #
  #   1. TRACE D'AUDIT — d'où vient ce paiement (quel SpaceBooking l'a généré).
  #   2. CLÉ D'IDEMPOTENCE de la rake — on ne recrée pas un Payment pour un
  #      (space_booking_id, status) déjà présent (voir la rake).
  #
  # Nullable : l'immense majorité des Payment (hébergement, Stripe, saisie
  # manuelle) n'en portent pas. Additive et réversible — dans l'esprit de
  # `AddStayToPayments` (issue #26). Aucune modification des colonnes existantes.
  def change
    add_column :payments, :space_booking_id, :bigint
    add_index :payments, :space_booking_id
    add_foreign_key :payments, :space_bookings, column: :space_booking_id
  end
end
