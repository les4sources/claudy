# Nombre de chiens du séjour (Michael, 2026-10-12). Le funnel et le formulaire
# admin le demandent, le devis facture le supplément chien, mais rien ne le
# gardait : rouvrir le séjour le remettait à zéro, et un simple
# réenregistrement retirait les 50 € du prix de l'hébergement. Les séjours
# existants partent à 0, faute de trace où le relire.
class AddDogsCountToStays < ActiveRecord::Migration[8.1]
  def change
    add_column :stays, :dogs_count, :integer, null: false, default: 0
  end
end
