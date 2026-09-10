module Gatherings
  # Rattache un rassemblement à ses pôles (epic #239, phase 2).
  #
  # DIFF, jamais supprimer-recréer. Détruire toutes les lignes pour les
  # remettre à l'identique fait perdre leur date de création, réveille les
  # callbacks de tout le monde à chaque enregistrement du formulaire, et
  # transformerait un jour un simple « j'ai corrigé l'heure » en notification de
  # rattachement pour trois pôles.
  #
  # La clé absente des paramètres ne veut PAS dire « aucun pôle » : le
  # formulaire de compte-rendu et la création rapide ne la portent pas, et
  # interpréter leur silence comme un détachement effacerait les rattachements
  # à chaque enregistrement.
  class SyncTeams
    def initialize(gathering:)
      @gathering = gathering
    end

    # `raw_ids` : le tableau soumis, `nil` quand la clé est absente.
    def run!(raw_ids)
      return if raw_ids.nil?

      submitted = Array(raw_ids).map(&:to_s).compact_blank.map(&:to_i).uniq
      current = @gathering.gathering_teams.pluck(:team_id)

      GatheringTeam.transaction do
        @gathering.gathering_teams.where(team_id: current - submitted).delete_all
        (submitted - current).each { |id| @gathering.gathering_teams.create!(team_id: id) }
      end

      @gathering.teams.reset
    end
  end
end
