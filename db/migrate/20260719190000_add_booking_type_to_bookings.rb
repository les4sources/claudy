# Persiste le mode d'occupation (epic #81, Phase 5 — revue Forge F2). Jusqu'ici
# `booking_type` était un attr_accessor éphémère : le mode « chambres seules »
# était re-DÉRIVÉ des Reservation à chaque édition, et dérivait faux si
# l'ensemble des chambres du gîte changeait après coup (chambre ajoutée →
# résa gîte entier relue comme chambres seules). Colonne nullable : le legacy
# reste dérivé, tout nouveau Booking porte son mode.
class AddBookingTypeToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :booking_type, :string
  end
end
