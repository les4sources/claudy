# L'IBAN d'une personne (epic #246, décision 5).
#
# Un cuisinier de batch cooking — un enfant y compris — se fait payer par
# virement : sans IBAN sur sa fiche, son compte créditeur reste un chiffre qu'on
# ne peut pas solder. Pour un enfant, l'IBAN est celui d'un parent, d'où le
# libellé « titulaire » libre : virer sur un compte dont le nom ne correspond pas
# à la personne payée doit rester explicable.
#
# La colonne était prévue par l'epic #241 phase 1 ; elle n'est pas sur `main`,
# on la pose ici à l'identique.
class AddIbanToHumans < ActiveRecord::Migration[8.1]
  def change
    add_column :humans, :iban, :text
    add_column :humans, :iban_holder_name, :string
  end
end
