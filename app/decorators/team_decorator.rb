class TeamDecorator < ApplicationDecorator
  delegate_all

  UNCLASSIFIED_LABEL = "Non classé".freeze

  # Les pôles pour un `<select>`, groupés par nature (`Team::KIND_LABELS`) et
  # triés par nom dans chaque groupe — à passer à `grouped_options_for_select`.
  # Les pôles pas encore classés par le collectif forment un dernier groupe :
  # sans lui, ils seraient impossibles à choisir.
  def self.grouped_options(teams = Team.all)
    by_kind = teams.sort_by { |team| team.name.to_s.downcase }.group_by(&:kind)
    (Team::KINDS + [nil]).filter_map do |kind|
      next if by_kind[kind].blank?
      [kind ? Team::KIND_LABELS.fetch(kind) : UNCLASSIFIED_LABEL, by_kind[kind].map { |team| [team.name, team.id] }]
    end
  end
end
