# Le rattachement d'un rassemblement à un pôle (epic #239, phase 2).
#
# Jointure nue, et volontairement : aucun rôle, aucun ordre. Un rassemblement
# sans aucun pôle est TRANSVERSAL — c'est l'absence de ligne qui le dit, pas un
# drapeau de plus à tenir à jour.
# == Schema Information
#
# Table name: gathering_teams
#
#  id           :bigint           not null, primary key
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  gathering_id :bigint           not null
#  team_id      :bigint           not null
#
# Indexes
#
#  index_gathering_teams_on_gathering_id              (gathering_id)
#  index_gathering_teams_on_gathering_id_and_team_id  (gathering_id,team_id) UNIQUE
#  index_gathering_teams_on_team_id                   (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (gathering_id => gatherings.id)
#  fk_rails_...  (team_id => teams.id)
#
class GatheringTeam < ApplicationRecord
  belongs_to :gathering
  belongs_to :team

  validates :team_id, uniqueness: { scope: :gathering_id }
end
