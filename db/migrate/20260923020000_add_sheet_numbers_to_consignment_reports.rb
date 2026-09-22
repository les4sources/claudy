# Les numéros des feuilles papier encodées dans un relevé (epic #359, phase 2) :
# l'artisan note « 7, 8 » en encodant, et l'on retrouve le papier si un doute
# surgit. Texte libre — une feuille remplacée à la main n'a pas toujours de
# numéro propre.
class AddSheetNumbersToConsignmentReports < ActiveRecord::Migration[8.1]
  def change
    add_column :consignment_reports, :sheet_numbers, :string
  end
end
