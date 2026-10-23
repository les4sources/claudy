# Durée réellement prestée d'une activité sur un séjour (Michael, 2026-10-23 :
# les ânes de Béné, 2 h de durée standard, 1 h 30 avec des tout-petits). Vide = la durée
# standard de l'activité ; c'est elle qui fait la rémunération du porteur.
class AddDurationMinutesToExperienceBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :experience_bookings, :duration_minutes, :integer
  end
end
