# Le pôle dont relève une action de cycle (epic #330, phase 5). Facultatif :
# la plupart des actions n'en ont pas, et le lien ne sert qu'à afficher.
class AddTeamToCycleActions < ActiveRecord::Migration[8.1]
  def change
    add_reference :cycle_actions, :team, null: true, index: true, foreign_key: true
  end
end
