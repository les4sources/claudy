# Journal des appels reçus sur la ligne de garde : suivi et contrôle des coûts
# Twilio. Aucun enregistrement audio. `attempts` garde chaque <Dial> de la
# cascade (veilleur → suppléant → secours) avec son statut et sa durée.
class CreatePhoneCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :phone_calls do |t|
      t.string :call_sid, null: false
      t.string :from_number
      t.date :duty_date
      t.references :on_call_human, foreign_key: { to_table: :humans }
      t.string :outcome
      t.string :dial_call_status
      t.integer :dial_call_duration
      t.jsonb :attempts, null: false, default: []
      t.text :error
      t.timestamps
    end
    add_index :phone_calls, :call_sid, unique: true
    add_index :phone_calls, :created_at
  end
end
