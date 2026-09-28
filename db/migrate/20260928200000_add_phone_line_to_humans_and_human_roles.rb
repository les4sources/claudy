# Ligne de garde (Twilio) : le webhook voix redirige l'appel vers le mobile du
# veilleur de garde. Il faut donc un numéro par membre (E.164) et, quand
# plusieurs veilleurs sont titulaires le même jour, savoir lequel tient le
# téléphone.
class AddPhoneLineToHumansAndHumanRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :humans, :phone, :string
    add_column :human_roles, :phone_holder, :boolean, default: false, null: false
  end
end
