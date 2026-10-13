# Une activité a un porteur principal, mais d'autres personnes peuvent tenir
# la prestation (Michael, 2026-10-13) : Magali fait un bain d'ânes dont Béné
# est la porteuse, Manon anime un atelier bijoux d'Olivier. C'est la personne
# qui a TENU la prestation qu'on rémunère. Vide = le porteur de l'activité.
class AddPerformedByToExperienceBookings < ActiveRecord::Migration[8.1]
  def change
    add_reference :experience_bookings, :performed_by, foreign_key: { to_table: :humans }, null: true
  end
end
